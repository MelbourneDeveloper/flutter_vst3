
#if defined(__linux__) && defined(FLUTTER_VST3_HAS_FLUTTER)


struct LinuxFlutterHost {
    std::function<void()> onFailure;
    guint watchdog{0};
    static inline bool sUiAlive{false};
    static inline bool sEngineFailed{false};
    GtkWidget* plug{nullptr};
    guint idleSourceId{0};
    void* parentWindow{nullptr};
    int width{600};
    int height{650};
    bool mounted{false};
    EditController* controller{nullptr};

    static inline GtkWidget* sSharedPlug{nullptr};
    static inline FlView* sSharedView{nullptr};
    static inline FlMethodChannel* sSharedChannel{nullptr};
    static inline Steinberg::Vst::EditController* sActiveController{nullptr};

    static std::string getModuleDirectory() {
        Dl_info info;
        if (dladdr(reinterpret_cast<void*>(&createEmbeddedFlutterView), &info) && info.dli_fname) {
            std::string path(info.dli_fname);
            size_t lastSlash = path.find_last_of('/');
            if (lastSlash != std::string::npos) {
                return path.substr(0, lastSlash);
            }
        }
        return "";
    }

    static bool checkHasFlutter() {
        std::string modDir = getModuleDirectory();
        if (sEngineFailed || modDir.empty()) return false;
        std::string assetsDir = modDir + "/data/flutter_assets";
        struct stat st;
        return stat(assetsDir.c_str(), &st) == 0 && S_ISDIR(st.st_mode)
            && stat((modDir + "/data/icudtl.dat").c_str(), &st) == 0
            && (stat((modDir + "/lib/libapp.so").c_str(), &st) == 0
                || stat((modDir + "/libapp.so").c_str(), &st) == 0
                || stat((assetsDir + "/kernel_blob.bin").c_str(), &st) == 0);
    }

    bool init(void* parentX11, Steinberg::Vst::EditController* ctrl, int w, int h) {
        if (sActiveController && sActiveController != ctrl) return false;
        if (!gdk_display_get_default() && !getenv("GDK_BACKEND"))
            gdk_set_allowed_backends("x11");
        if (!gtk_init_check(nullptr, nullptr) || !GDK_IS_X11_DISPLAY(gdk_display_get_default())) return false;
        parentWindow = parentX11;
        width = w;
        height = h;
        mounted = false;
        controller = ctrl;
        sActiveController = ctrl;

        // Post-mount via GLib timeout so it executes on the platform thread
        // AFTER the host Dart FFI call (openEditorWindow) has returned to the event loop.
        // This avoids Dart VM asserting "CreateIsolate expects there to be no current isolate"
        // when the second Flutter engine spins up its isolate.
        idleSourceId = g_timeout_add(50, +[](gpointer data) -> gboolean {
            auto* self = static_cast<LinuxFlutterHost*>(data);
            self->idleSourceId = 0;
            self->mount();
            return G_SOURCE_REMOVE;
        }, this);
        return true;
    }

    static void onMethodCall(FlMethodChannel* ch, FlMethodCall* methodCall, gpointer userData) {
        sUiAlive = true;
        const gchar* name = fl_method_call_get_name(methodCall);
        FlValue* args = fl_method_call_get_args(methodCall);
        auto* ctrl = sActiveController;

        if (g_strcmp0(name, "getInitialParameters") == 0) {
            g_autoptr(FlValue) map = fl_value_new_map();
            if (ctrl) {
                int count = ctrl->getParameterCount();
                for (int i = 0; i < count; ++i) {
                    Steinberg::Vst::ParameterInfo info{};
                    if (ctrl->getParameterInfo(i, info) == Steinberg::kResultTrue) {
                        g_autofree gchar* key = g_strdup_printf("%u", info.id);
                        fl_value_set_string_take(
                            map, key,
                            fl_value_new_float(ctrl->getParamNormalized(info.id)));
                    }
                }
            }
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
            fl_method_call_respond(methodCall, resp, nullptr);
        } else if (g_strcmp0(name, "beginEdit") == 0 || g_strcmp0(name, "endEdit") == 0) {
            FlValue* id = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                ? fl_value_lookup_string(args, "id") : nullptr;
            if (!ctrl || !id || fl_value_get_type(id) != FL_VALUE_TYPE_INT) {
                fl_method_call_respond_error(methodCall, "INVALID_ARGUMENTS", "Expected parameter id", nullptr, nullptr);
                return;
            }
            const auto pid = static_cast<ParamID>(fl_value_get_int(id));
            g_strcmp0(name, "beginEdit") == 0 ? ctrl->beginEdit(pid) : ctrl->endEdit(pid);
            fl_method_call_respond_success(methodCall, nullptr, nullptr);
        } else if (g_strcmp0(name, "setParameter") == 0) {
            if (ctrl && args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
                FlValue* idVal = fl_value_lookup_string(args, "id");
                FlValue* valVal = fl_value_lookup_string(args, "value");
                if (idVal && valVal) {
                    int64_t pid = (fl_value_get_type(idVal) == FL_VALUE_TYPE_INT)
                        ? fl_value_get_int(idVal)
                        : static_cast<int64_t>(fl_value_get_float(idVal));
                    double val = (fl_value_get_type(valVal) == FL_VALUE_TYPE_FLOAT)
                        ? fl_value_get_float(valVal)
                        : static_cast<double>(fl_value_get_int(valVal));
                    applyUiEdit(ctrl, static_cast<ParamID>(pid), val);
                }
            }
            g_autoptr(FlValue) ret = fl_value_new_bool(TRUE);
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_success_response_new(ret));
            fl_method_call_respond(methodCall, resp, nullptr);
        } else if (g_strcmp0(name, "getSharedMemoryInfo") == 0) {
            g_autoptr(FlValue) map = fl_value_new_map();
            uintptr_t addr = controllerShmAddress(ctrl);
            fl_value_set_string_take(map, "address", fl_value_new_int(static_cast<int64_t>(addr)));
            fl_value_set_string_take(map, "totalSize", fl_value_new_int(static_cast<int64_t>(VST3_SHM_TOTAL_SIZE)));
            fl_value_set_string_take(map, "maxSamples", fl_value_new_int(static_cast<int64_t>(VST3_SHM_MAX_SAMPLES)));
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
            fl_method_call_respond(methodCall, resp, nullptr);
        } else {
            g_autoptr(FlMethodResponse) resp = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
            fl_method_call_respond(methodCall, resp, nullptr);
        }
    }

    void mount() {
        if (!flutter_vst3::ownsEditor(sActiveController, controller) || mounted || !parentWindow) return;
        mounted = true;

        Display* xdpy = gdk_x11_get_default_xdisplay();

        if (!sSharedPlug) {
            sSharedPlug = gtk_plug_new((Window)(uintptr_t)parentWindow);
            if (!sSharedPlug) {
                fprintf(stderr, "flutter_vst3: gtk_plug_new failed. VST3 GUI embedding on Linux requires an X11 backend (GDK_BACKEND=x11).\n");
                fail();
                return;
            }
            g_object_ref_sink(sSharedPlug);
            g_signal_connect(sSharedPlug, "delete-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer) -> gboolean {
                return TRUE;
            }), nullptr);
            gtk_widget_set_size_request(sSharedPlug, width, height);
            gtk_widget_realize(sSharedPlug);
            gtk_widget_show(sSharedPlug);

            gdk_gl_context_clear_current();

            std::string modDir = getModuleDirectory();
            std::string assetsPath = modDir + "/data/flutter_assets";
            std::string icuPath = modDir + "/data/icudtl.dat";

            FlDartProject* proj = fl_dart_project_new();
            fl_dart_project_set_assets_path(proj, const_cast<gchar*>(assetsPath.c_str()));
            fl_dart_project_set_icu_data_path(proj, const_cast<gchar*>(icuPath.c_str()));

            std::string aotPath = modDir + "/lib/libapp.so";
            struct stat aotSt;
            if (stat(aotPath.c_str(), &aotSt) != 0) {
                aotPath = modDir + "/libapp.so";
            }
            if (stat(aotPath.c_str(), &aotSt) == 0) {
                fl_dart_project_set_aot_library_path(proj, aotPath.c_str());
            }

            watchdog = g_timeout_add(flutter_vst3::kFlutterStartTimeoutMs, +[](gpointer data) -> gboolean {
                auto* self = static_cast<LinuxFlutterHost*>(data);
                self->watchdog = 0;
                if (flutter_vst3::flutterStartFailed(sUiAlive, sEngineFailed, sActiveController != nullptr)) self->fail();
                return G_SOURCE_REMOVE;
            }, this);
            sSharedView = fl_view_new(proj);
            g_object_unref(proj);
            if (!sSharedView) { fail(); return; }
            g_object_ref_sink(sSharedView);

            FlEngine* engine = fl_view_get_engine(sSharedView);
            FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
            g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
            sSharedChannel = fl_method_channel_new(messenger, "flutter_vst3/parameters", FL_METHOD_CODEC(codec));
            fl_method_channel_set_method_call_handler(sSharedChannel, onMethodCall, nullptr, nullptr);

            gtk_container_add(GTK_CONTAINER(sSharedPlug), GTK_WIDGET(sSharedView));
        } else {
            // Re-embed existing persistent plug into the new parentWindow if different
            GdkWindow* plugWin = gtk_widget_get_window(sSharedPlug);
            if (plugWin && xdpy) {
                Window plugXid = gdk_x11_window_get_xid(plugWin);
                if (plugXid) {
                    Window currentParent = 0;
                    Window rootRet = 0;
                    Window* childrenRet = nullptr;
                    unsigned int nchildrenRet = 0;
                    if (XQueryTree(xdpy, plugXid, &rootRet, &currentParent, &childrenRet, &nchildrenRet)) {
                        if (childrenRet) XFree(childrenRet);
                    }
                    if (currentParent != (Window)(uintptr_t)parentWindow) {
                        auto* parent = gdk_x11_window_foreign_new_for_display(
                            gdk_display_get_default(), (Window)(uintptr_t)parentWindow);
                        if (!parent) { fail(); return; }
                        gdk_window_reparent(plugWin, parent, 0, 0);
                        g_object_unref(parent);
                    }
                    XResizeWindow(xdpy, plugXid, width, height);
                }
            }
        }

        plug = sSharedPlug;
        gtk_widget_set_size_request(plug, width, height);
        gtk_widget_show_all(plug);

        GdkWindow* plugWin = gtk_widget_get_window(plug);
        if (plugWin) {
            gdk_window_show(plugWin);
            Window plugXid = gdk_x11_window_get_xid(plugWin);
            if (xdpy && plugXid) {
                XMapRaised(xdpy, plugXid);
                XFlush(xdpy);
            }
        }

        // On reopen, synchronize parameters and notify Flutter UI that host is attached
        if (sSharedChannel) {
            fl_method_channel_invoke_method(sSharedChannel, "onHostAttached", nullptr, nullptr, nullptr, nullptr);
            if (sActiveController) {
                int count = sActiveController->getParameterCount();
                for (int i = 0; i < count; ++i) {
                    Steinberg::Vst::ParameterInfo info{};
                    if (sActiveController->getParameterInfo(i, info) == Steinberg::kResultTrue) {
                        updateParam(info.id, sActiveController->getParamNormalized(info.id));
                    }
                }
            }
        }
    }

    void updateParam(Steinberg::Vst::ParamID pid, Steinberg::Vst::ParamValue val) {
        if (!flutter_vst3::ownsEditor(sActiveController, controller) || !sSharedChannel) return;
        g_autoptr(FlValue) args = fl_value_new_map();
        fl_value_set_string_take(args, "id", fl_value_new_int(static_cast<int64_t>(pid)));
        fl_value_set_string_take(args, "value", fl_value_new_float(static_cast<double>(val)));
        fl_method_channel_invoke_method(sSharedChannel, "onParameterChanged", args, nullptr, nullptr, nullptr);
    }

    void fail() {
        if (watchdog) { g_source_remove(watchdog); watchdog = 0; }
        sEngineFailed = true;
        g_clear_object(&sSharedChannel);
        if (sSharedPlug) gtk_widget_destroy(sSharedPlug);
        g_clear_object(&sSharedView);
        g_clear_object(&sSharedPlug);
        plug = nullptr;
        sActiveController = nullptr;
        mounted = false;
        if (onFailure) onFailure();
    }

    static GtkWidget* findEventBox(GtkWidget* widget) {
        if (GTK_IS_EVENT_BOX(widget)) return widget;
        if (!GTK_IS_CONTAINER(widget)) return nullptr;
        GtkWidget* found = nullptr;
        GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
        for (GList* child = children; child && !found; child = child->next) {
            found = findEventBox(GTK_WIDGET(child->data));
        }
        g_list_free(children);
        return found;
    }

    /// Ends Flutter's drag before its window hides. Its embedder would otherwise
    /// wait for a release that goes elsewhere, and ignore the next press.
    static void releasePointer() {
        GtkWidget* box = findEventBox(sSharedPlug);
        GdkWindow* window = box ? gtk_widget_get_window(box) : nullptr;
        if (!window) return;
        GdkEvent* event = gdk_event_new(GDK_BUTTON_RELEASE);
        event->button.window = GDK_WINDOW(g_object_ref(window));
        event->button.send_event = TRUE;
        event->button.time = GDK_CURRENT_TIME;
        event->button.button = 1;
        event->button.state = GDK_BUTTON1_MASK;
        gdk_event_set_device(event, gdk_seat_get_pointer(gdk_display_get_default_seat(gdk_window_get_display(window))));
        gtk_widget_event(box, event);
        gdk_event_free(event);
    }

    void shutdown() {
        if (watchdog) { g_source_remove(watchdog); watchdog = 0; }
        if (idleSourceId != 0) {
            g_source_remove(idleSourceId);
            idleSourceId = 0;
        }
        if (!flutter_vst3::ownsEditor(sActiveController, controller)) return;
        if (sSharedChannel) {
            fl_method_channel_invoke_method(sSharedChannel, "onHostDetached", nullptr, nullptr, nullptr, nullptr);
        }
        if (sSharedPlug) {
            releasePointer();
            gtk_widget_hide(sSharedPlug);
            auto* window = gtk_widget_get_window(sSharedPlug);
            auto* display = gdk_x11_get_default_xdisplay();
            if (window && display) {
                gdk_window_reparent(window, gdk_get_default_root_window(), 0, 0);
                XSync(display, False);
                while (gtk_events_pending()) gtk_main_iteration_do(FALSE);
            }
        }
        gdk_gl_context_clear_current();
        plug = nullptr;
        sActiveController = nullptr;
        mounted = false;
        parentWindow = nullptr;
    }
};
#else
struct LinuxFlutterHost {
    GtkWidget* plug{nullptr};
    static bool checkHasFlutter() { return false; }
    bool init(void*, Steinberg::Vst::EditController*, int, int) { return false; }
    void updateParam(Steinberg::Vst::ParamID, Steinberg::Vst::ParamValue) {}
    void shutdown() {}
};
#endif
