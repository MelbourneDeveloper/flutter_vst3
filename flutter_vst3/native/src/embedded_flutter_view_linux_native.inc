
struct LinuxNativeParamRow {
    Steinberg::Vst::ParamID id{0};
    GtkWidget* valLabel{nullptr};
    GtkWidget* scale{nullptr};
    GtkAdjustment* adj{nullptr};
};

class LinuxNativeEditorHost {
public:
    GtkWidget* plug{nullptr};
    GtkWidget* mainBox{nullptr};
    GtkCssProvider* cssProvider{nullptr};
    Steinberg::Vst::EditController* controller{nullptr};
    std::string pluginName;
    std::vector<LinuxNativeParamRow> rows;
    bool inScroll{false};
    guint idleSourceId{0};
    void* parentWindow{nullptr};
    int width{540};
    int height{400};

    bool init(void* parentX11, Steinberg::Vst::EditController* ctrl, const std::string& name, int w, int h) {
        if (!gdk_display_get_default() && !getenv("GDK_BACKEND"))
            gdk_set_allowed_backends("x11");
        if (!gtk_init_check(nullptr, nullptr) || !GDK_IS_X11_DISPLAY(gdk_display_get_default())) return false;
        parentWindow = parentX11;
        controller = ctrl;
        pluginName = name;
        width = w;
        height = h;

        mount();
        return plug != nullptr;
    }

    void mount() {
        if (!parentWindow) return;
        plug = gtk_plug_new((Window)(uintptr_t)parentWindow);
        if (!plug) {
            fprintf(stderr, "flutter_vst3: gtk_plug_new failed. VST3 GUI embedding on Linux requires an X11 backend (GDK_BACKEND=x11).\n");
            return;
        }

        gtk_widget_set_size_request(plug, width, height);
        gtk_style_context_add_class(gtk_widget_get_style_context(plug), "vst3-native-editor");

        if (!cssProvider) {
            cssProvider = gtk_css_provider_new();
            const char* css =
                ".vst3-native-editor, .vst3-native-editor box { background-color: #17171c; color: #e6e6eb; }"
                ".vst3-native-editor label.plugin-title { font-size: 16pt; font-weight: bold; color: #ffffff; }"
                ".vst3-native-editor label.plugin-sub { font-size: 10pt; color: #888899; }"
                ".vst3-native-editor label.param-name { font-size: 11pt; font-weight: 600; color: #e6e6eb; }"
                ".vst3-native-editor label.param-val { font-size: 11pt; font-weight: bold; color: #40c0ff; font-family: monospace; }"
                ".vst3-native-editor label.footer { font-size: 9pt; color: #666677; }"
                ".vst3-native-editor scale contents trough { min-height: 4px; background-color: #2d2d37; border-radius: 2px; }"
                ".vst3-native-editor scale contents trough highlight { background-color: #40c0ff; border-radius: 2px; }"
                ".vst3-native-editor scale contents trough slider { min-width: 16px; min-height: 16px; margin: -6px; border-radius: 8px; background-color: #ffffff; }";
            gtk_css_provider_load_from_data(cssProvider, css, -1, nullptr);
            gtk_style_context_add_provider_for_screen(
                gdk_screen_get_default(),
                GTK_STYLE_PROVIDER(cssProvider),
                GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        mainBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
        gtk_style_context_add_class(gtk_widget_get_style_context(mainBox), "vst3-native-editor");
        gtk_widget_set_margin_start(mainBox, 24);
        gtk_widget_set_margin_end(mainBox, 24);
        gtk_widget_set_margin_top(mainBox, 16);
        gtk_widget_set_margin_bottom(mainBox, 16);

        // Title
        GtkWidget* titleLbl = gtk_label_new(pluginName.empty() ? "VST3 Plugin" : pluginName.c_str());
        gtk_widget_set_halign(titleLbl, GTK_ALIGN_START);
        gtk_style_context_add_class(gtk_widget_get_style_context(titleLbl), "plugin-title");
        gtk_box_pack_start(GTK_BOX(mainBox), titleLbl, FALSE, FALSE, 0);

        // Subtitle
        GtkWidget* subLbl = gtk_label_new("flutter_vst3 \u2022 Pure Dart DSP & UI");
        gtk_widget_set_halign(subLbl, GTK_ALIGN_START);
        gtk_style_context_add_class(gtk_widget_get_style_context(subLbl), "plugin-sub");
        gtk_box_pack_start(GTK_BOX(mainBox), subLbl, FALSE, FALSE, 0);

        // Separator
        GtkWidget* sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
        gtk_box_pack_start(GTK_BOX(mainBox), sep, FALSE, FALSE, 6);

        // Parameter rows
        rows.clear();
        if (controller) {
            int count = controller->getParameterCount();
            for (int i = 0; i < count; ++i) {
                Steinberg::Vst::ParameterInfo info{};
                if (controller->getParameterInfo(i, info) != Steinberg::kResultTrue) continue;

                LinuxNativeParamRow row;
                row.id = info.id;

                char asciiTitle[128] = {0};
                Steinberg::UString128(info.title).toAscii(asciiTitle, sizeof(asciiTitle));

                GtkWidget* rowBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);

                GtkWidget* headerBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
                GtkWidget* nameLbl = gtk_label_new(asciiTitle[0] != '\0' ? asciiTitle : "Param");
                gtk_widget_set_halign(nameLbl, GTK_ALIGN_START);
                gtk_style_context_add_class(gtk_widget_get_style_context(nameLbl), "param-name");
                gtk_box_pack_start(GTK_BOX(headerBox), nameLbl, TRUE, TRUE, 0);

                row.valLabel = gtk_label_new("");
                gtk_widget_set_halign(row.valLabel, GTK_ALIGN_END);
                gtk_style_context_add_class(gtk_widget_get_style_context(row.valLabel), "param-val");
                gtk_box_pack_start(GTK_BOX(headerBox), row.valLabel, FALSE, FALSE, 0);

                gtk_box_pack_start(GTK_BOX(rowBox), headerBox, FALSE, FALSE, 0);

                double currentVal = controller->getParamNormalized(info.id);
                row.adj = gtk_adjustment_new(currentVal, 0.0, 1.0, 0.001, 0.01, 0.0);
                row.scale = gtk_scale_new(GTK_ORIENTATION_HORIZONTAL, row.adj);
                gtk_scale_set_draw_value(GTK_SCALE(row.scale), FALSE);
                gtk_box_pack_start(GTK_BOX(rowBox), row.scale, FALSE, FALSE, 0);

                struct CallbackData {
                    LinuxNativeEditorHost* self;
                    Steinberg::Vst::ParamID paramId;
                    size_t rowIndex;
                    bool editing{false};
                };
                auto* cbData = new CallbackData{this, info.id, rows.size()};
                g_object_set_data_full(G_OBJECT(row.scale), "gesture-data", cbData,
                    +[](gpointer user_data) {
                        auto* data = static_cast<CallbackData*>(user_data);
                        if (data->editing && data->self->controller)
                            data->self->controller->endEdit(data->paramId);
                        delete data;
                    });
                const auto begin = +[](GtkWidget*, GdkEvent*, gpointer user_data) -> gboolean {
                    auto* data = static_cast<CallbackData*>(user_data);
                    if (!data->editing && data->self->controller) {
                        data->editing = true;
                        data->self->controller->beginEdit(data->paramId);
                    }
                    return FALSE;
                };
                const auto end = +[](GtkWidget*, GdkEvent*, gpointer user_data) -> gboolean {
                    auto* data = static_cast<CallbackData*>(user_data);
                    if (data->editing && data->self->controller) {
                        data->self->controller->endEdit(data->paramId);
                        data->editing = false;
                    }
                    return FALSE;
                };
                g_signal_connect(row.scale, "button-press-event", G_CALLBACK(begin), cbData);
                g_signal_connect(row.scale, "key-press-event", G_CALLBACK(begin), cbData);
                g_signal_connect_after(row.scale, "button-release-event", G_CALLBACK(end), cbData);
                g_signal_connect_after(row.scale, "key-release-event", G_CALLBACK(end), cbData);
                g_signal_connect_data(row.adj, "value-changed",
                    G_CALLBACK(+[](GtkAdjustment* adj, gpointer user_data) {
                        auto* data = static_cast<CallbackData*>(user_data);
                        if (data->self->inScroll || !data->self->controller) return;
                        data->self->inScroll = true;
                        double val = gtk_adjustment_get_value(adj);
                        if (!data->editing) data->self->controller->beginEdit(data->paramId);
                        data->self->controller->setParamNormalized(data->paramId, val);
                        data->self->controller->performEdit(data->paramId, val);
                        if (!data->editing) data->self->controller->endEdit(data->paramId);
                        data->self->updateValueLabel(data->self->rows[data->rowIndex], val);
                        data->self->inScroll = false;
                    }),
                    cbData,
                    nullptr,
                    G_CONNECT_AFTER);

                updateValueLabel(row, currentVal);
                gtk_box_pack_start(GTK_BOX(mainBox), rowBox, FALSE, FALSE, 4);
                rows.push_back(row);
            }

            // Footer
            GtkWidget* footer = gtk_label_new("Shared Memory DSP");
            gtk_widget_set_halign(footer, GTK_ALIGN_CENTER);
            gtk_style_context_add_class(gtk_widget_get_style_context(footer), "footer");
            gtk_box_pack_start(GTK_BOX(mainBox), footer, FALSE, FALSE, 8);
        }

        gtk_container_add(GTK_CONTAINER(plug), mainBox);
        gtk_widget_show_all(plug);

        GdkWindow* plugWin = gtk_widget_get_window(plug);
        if (plugWin) {
            gdk_window_show(plugWin);
            Window plugXid = gdk_x11_window_get_xid(plugWin);
            Display* xdpy = gdk_x11_get_default_xdisplay();
            if (xdpy && plugXid) {
                XMapRaised(xdpy, plugXid);
                XFlush(xdpy);
            }
        }
    }

    void updateValueLabel(LinuxNativeParamRow& row, double val) {
        if (!row.valLabel) return;
        char buf[128];
        if (controller) {
            Steinberg::Vst::String128 str128;
            if (controller->getParamStringByValue(row.id, val, str128) == Steinberg::kResultTrue) {
                Steinberg::UString128(str128).toAscii(buf, sizeof(buf));
                gtk_label_set_text(GTK_LABEL(row.valLabel), buf);
                return;
            }
        }
        snprintf(buf, sizeof(buf), "%.2f", val);
        gtk_label_set_text(GTK_LABEL(row.valLabel), buf);
    }

    void updateParam(Steinberg::Vst::ParamID paramId, Steinberg::Vst::ParamValue val) {
        if (inScroll) return;
        for (auto& r : rows) {
            if (r.id == paramId) {
                inScroll = true;
                if (r.adj) {
                    gtk_adjustment_set_value(r.adj, val);
                }
                updateValueLabel(r, val);
                inScroll = false;
                break;
            }
        }
    }

    void shutdown() {
        if (idleSourceId != 0) {
            g_source_remove(idleSourceId);
            idleSourceId = 0;
        }
        if (cssProvider) {
            gtk_style_context_remove_provider_for_screen(
                gdk_screen_get_default(),
                GTK_STYLE_PROVIDER(cssProvider));
            g_object_unref(cssProvider);
            cssProvider = nullptr;
        }
        if (plug) {
            gtk_widget_destroy(plug);
            gdk_display_sync(gdk_display_get_default());
            plug = nullptr;
            mainBox = nullptr;
        }
        rows.clear();
        parentWindow = nullptr;
    }
};
