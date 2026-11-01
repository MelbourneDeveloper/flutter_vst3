inline HINSTANCE editorModule() {
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&createEmbeddedFlutterView), &module);
    return module;
}
inline std::wstring editorClassName(const wchar_t* role) {
    return std::wstring(role) + L"_" + std::to_wstring(reinterpret_cast<uintptr_t>(editorModule()));
}
