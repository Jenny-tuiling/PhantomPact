#include "local_io.hpp"

#include "pad_route.hpp"
#include "screens.hpp"

namespace {

constexpr DWORD POLL_MS = 250;
constexpr DWORD NATIVE_EVERY_MS = 2000;
constexpr DWORD PADS_MS = 20;
constexpr DWORD FREE_DELAY_MS = 250;
constexpr DWORD FREE_CLICK_MS = 30;

LONG started = 0;
HMODULE self = nullptr;
std::wstring mod_root;     // ...\Mods\PBZCoop
std::wstring mod_dir;      // mod_root, or mod_root\instN for copy N

void find_folders() {
    wchar_t path[MAX_PATH * 4];
    DWORD n = GetModuleFileNameW(self, path, static_cast<DWORD>(std::size(path)));
    std::wstring dll(path, n);
    std::wstring dlls = dll.substr(0, dll.find_last_of(L'\\'));
    mod_root = dlls.substr(0, dlls.find_last_of(L'\\'));
    mod_dir = mod_root;
    wchar_t instance[16];
    const DWORD got = GetEnvironmentVariableW(L"PBZCOOP_INSTANCE", instance, 16);     // (16 or more: not written whole)
    if (got > 0 && got < 16 && _wtoi(instance) > 1)
        mod_dir += L"\\inst" + std::wstring(instance);
}

// In local co-op (pads_watch.txt exists) the joysticks' state goes to pads.txt, one line per XInput slot: "0" unplugged,
// "1" plugged in, "2" with a button held. While the panel is open (pads_want.txt exists) that's faster, and the cursor,
// left button, Escape, F4 or F5 and whether this game has the focus go to mouse.txt: the panel lets go of the mouse, and then the
// game itself sees no input.
// XInput is loaded here, not linked, so a PC without it still runs.
bool down(int key) {
    return (GetAsyncKeyState(key) & 0x8000) != 0;
}

// The game keeps the real cursor pinned to the screen's centre until a click lands, whatever the input mode: click once
// for the player as the panel opens, on the panel's empty middle, and again each time the game gets the focus back. False
// while the cursor is over something else: a click there would land on that window. That includes UE4SS's console, which
// Windows counts as this game's own: a click in it starts a text selection, and every log line then waits on it (the
// game froze that way on the bench, its window over two monitors with the console on top).
bool free_cursor() {
    HWND window = GetForegroundWindow();
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    POINT cursor{};
    if (process != GetCurrentProcessId() || !GetCursorPos(&cursor)) return false;
    HWND under = WindowFromPoint(cursor);
    GetWindowThreadProcessId(under, &process);
    if (process != GetCurrentProcessId()) return false;
    wchar_t cls[32] = {};
    if (!GetClassNameW(GetAncestor(under, GA_ROOT), cls, 32) || wcscmp(cls, L"UnrealWindow") != 0) return false;
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    Sleep(FREE_CLICK_MS);
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    return true;
}

DWORD WINAPI pads_thread(void*) {
    struct State { DWORD packet; WORD buttons; BYTE left, right; SHORT lx, ly, rx, ry; };
    using GetState = DWORD(WINAPI*)(DWORD, State*);
    HMODULE lib = LoadLibraryW(L"xinput1_4.dll");
    if (!lib) lib = LoadLibraryW(L"xinput9_1_0.dll");
    auto get = lib ? reinterpret_cast<GetState>(GetProcAddress(lib, "XInputGetState")) : nullptr;
    if (!get) return 0;
    const std::wstring want = mod_dir + L"\\pads_want.txt";
    const std::wstring watch = mod_dir + L"\\pads_watch.txt";
    const std::wstring path = mod_dir + L"\\pads.txt";
    bool was_open = false, had_focus = false, free_due = false;
    while (true) {
        const bool open = GetFileAttributesW(want.c_str()) != INVALID_FILE_ATTRIBUTES;
        if (open || GetFileAttributesW(watch.c_str()) != INVALID_FILE_ATTRIBUTES) {
            std::string text;
            LONG pads = 0;
            for (DWORD i = 0; i < 4; i++) {
                State s{};
                bool on = get(i, &s) == ERROR_SUCCESS;
                pads += on ? 1 : 0;
                text += !on ? "0\n" : ((s.buttons != 0 || s.left > 64 || s.right > 64) ? "2\n" : "1\n");
            }
            localio::write_atomic(path, text);
            route::xinput_pads = pads;
        }
        if (open) {
            HWND window = GetForegroundWindow();
            DWORD owner = 0;
            GetWindowThreadProcessId(window, &owner);
            const bool focus = owner == GetCurrentProcessId();
            if (!was_open || (focus && !had_focus)) {
                free_due = true;
                Sleep(FREE_DELAY_MS);
            }
            had_focus = focus;
            if (free_due && free_cursor()) free_due = false;
            ClipCursor(nullptr);
            POINT cursor{};
            if (GetCursorPos(&cursor) && window && ScreenToClient(window, &cursor))
                localio::write_atomic(mod_dir + L"\\mouse.txt",
                                    std::to_string(cursor.x) + " " + std::to_string(cursor.y) + " "
                                        + (down(VK_LBUTTON) ? "1 " : "0 ") + (down(VK_ESCAPE) ? "1 " : "0 ")
                                        + ((down(VK_F4) || down(VK_F5) || down(VK_F6)) ? "1 " : "0 ")   // F6: PvP's page
                                        + (focus ? "1\n" : "0\n"));   // this game has the focus
            Sleep(PADS_MS);
        } else {
            Sleep(POLL_MS);
        }
        was_open = open;
    }
}


DWORD WINAPI handshake(void*) {
 while(true){
  FILE* f=nullptr;char nonce[100]={};
  if(_wfopen_s(&f,(mod_dir+L"\\local_base_probe.txt").c_str(),L"rb")==0 && f){fgets(nonce,99,f);fclose(f);}
  std::string n(nonce);if(!n.empty() && n.size()<90 && n.find_first_not_of("0123456789abcdef-")==std::string::npos)
   localio::write_atomic(mod_dir+L"\\local_base_native.txt","PBZLOCAL1 "+n+" local-0.1.0");
  Sleep(100);
 }
 return 0;
}
}
extern "C" __declspec(dllexport) void* start_mod(){
 if(InterlockedExchange(&started,1)==0){find_folders();
  CloseHandle(CreateThread(nullptr,0,pads_thread,nullptr,0,nullptr));
  CloseHandle(CreateThread(nullptr,0,route::watch,&mod_dir,0,nullptr));
  CloseHandle(CreateThread(nullptr,0,screens::watch,&mod_dir,0,nullptr));
  CloseHandle(CreateThread(nullptr,0,handshake,nullptr,0,nullptr));
 }return nullptr;
}
extern "C" __declspec(dllexport) void uninstall_mod(void*){recoverykeys::shutdown();}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}
