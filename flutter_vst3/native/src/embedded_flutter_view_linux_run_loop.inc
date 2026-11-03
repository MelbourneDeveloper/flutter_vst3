/// Bridges GLib sources to the host UI run loop, without a background GTK thread.
class LinuxGlibPump : public Linux::ITimerHandler, public FObject {
public:
    ~LinuxGlibPump() override { stop(); }
    void setFrame(IPlugFrame* frame) {
        stop();
        if (!frame || frame->queryInterface(Linux::IRunLoop::iid,
                reinterpret_cast<void**>(&loop_)) != kResultTrue) return;
        if (loop_->registerTimer(this, 10) != kResultTrue) {
            loop_->release();
            loop_ = nullptr;
        }
    }
    void stop() {
        if (!loop_) return;
        loop_->unregisterTimer(this);
        loop_->release();
        loop_ = nullptr;
    }
    void PLUGIN_API onTimer() override {
        for (int i = 0; i < 32 && g_main_context_pending(nullptr); ++i)
            g_main_context_iteration(nullptr, FALSE);
    }
    REFCOUNT_METHODS(FObject)
    tresult PLUGIN_API queryInterface(const TUID iid, void** obj) override {
        QUERY_INTERFACE(iid, obj, Linux::ITimerHandler::iid, Linux::ITimerHandler)
        return FObject::queryInterface(iid, obj);
    }
private:
    Linux::IRunLoop* loop_{nullptr};
};
