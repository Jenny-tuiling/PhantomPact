#include <windows.h>
#include <cassert>
#include <iostream>
#include "recovery_keyboard.hpp"
using namespace recoverykeys;
unsigned previousCalls=0;
LRESULT CALLBACK original(HWND window,UINT message,WPARAM wParam,LPARAM lParam){
    if(message==WM_APP+7 || message==WM_KEYDOWN || message==WM_KEYUP || message==WM_INPUT){++previousCalls;return 123;}
    return DefWindowProcW(window,message,wParam,lParam);
}
int main(){
    for(unsigned channel=0;channel<2;channel++)for(UINT key:{UINT('R'),UINT('F')}){
        Filter filter;
        assert(filter.consume(channel,key,true,true,true,true));
        assert(filter.consume(channel,key,true,false,false,true)); // repeats stay consumed
        assert(filter.consume(channel,key,false,false,false,false)); // paired release even after focus/modifier loss
        assert(!filter.consume(channel,key,false,true,true,true));
        assert(!filter.consume(channel,key,true,true,false,true));
        assert(!filter.consume(channel,key,true,true,true,true)); // delivered before chord: repeat must also pass
        assert(!filter.consume(channel,key,false,true,true,true));
        assert(filter.consume(channel,key,true,true,true,true));
        assert(filter.consume(channel,key,false,true,true,true));
        assert(!filter.consume(channel,key,true,true,true,false));
        assert(!filter.consume(channel,key,false,true,true,false));
        assert(!filter.consume(channel,'A',true,true,true,true));
        assert(!filter.consume(channel,VK_LCONTROL,true,true,true,true));
    }
    Filter independent;
    assert(independent.consume(0,'R',true,true,true,true));
    assert(independent.consume(1,'R',true,true,true,true));
    assert(independent.consume(0,'R',false,false,false,true));
    assert(independent.consume(1,'R',true,false,false,true));
    assert(independent.consume(1,'R',false,false,false,true));
    assert(!independent.consume(2,'R',true,true,true,true));
    independent.consume(0,'R',true,false,false,true);independent.focus_lost();
    assert(independent.consume(0,'R',true,true,true,true));
    assert(!ensure() && !available()); // this test process initially has no UnrealWindow
    const auto instance=GetModuleHandleW(nullptr);
    WNDCLASSW cls{};cls.hInstance=instance;cls.lpszClassName=L"UnrealWindow";cls.lpfnWndProc=original;
    assert(RegisterClassW(&cls));
    HWND window=CreateWindowExW(0,L"UnrealWindow",L"PBZ recovery isolated hidden fixture",WS_OVERLAPPED,0,0,20,20,nullptr,nullptr,instance,nullptr);
    assert(window && !IsWindowVisible(window));
    assert(target_window(window) && ensure() && available());
    assert(GetWindowLongPtrW(window,GWLP_WNDPROC)==reinterpret_cast<LONG_PTR>(&window_proc));
    assert(current->previous==&original);
    auto before=previousCalls;assert(SendMessageW(window,WM_APP+7,42,0)==123);assert(previousCalls==before+1);
    assert(SendMessageW(window,WM_KEYDOWN,'A',0)==123);assert(previousCalls==before+2);
    // Exercise the installed callback's paired-release path with a fixture
    // filter state. This sends a message only to this process's hidden window.
    current->filter.swallowed[0][0]=true;
    assert(SendMessageW(window,WM_KEYUP,'R',0)==0);assert(previousCalls==before+2);
    assert(SendMessageW(window,WM_KEYUP,'R',0)==123);assert(previousCalls==before+3);
    // An invalid/non-keyboard raw handle must fall through to the old WndProc.
    assert(SendMessageW(window,WM_INPUT,0,0)==123);assert(previousCalls==before+4);
    shutdown();assert(!available());
    assert(GetWindowLongPtrW(window,GWLP_WNDPROC)==reinterpret_cast<LONG_PTR>(&original));
    assert(SendMessageW(window,WM_KEYDOWN,'F',0)==123);
    DestroyWindow(window);UnregisterClassW(L"UnrealWindow",instance);
    std::cout<<"PASS keyboard: legacy/raw independent press-repeat-release, modifiers-first, no other keys/windows, failed install disables, hidden own-process UnrealWindow subclass/forward/restore. No real game/physical input used.\n";
}
