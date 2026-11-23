#pragma once
#include <windows.h>
#include <new>
#include <string>

// A subclass of this process's one UnrealWindow, never a global keyboard hook.
// Both legacy and WM_INPUT keyboard paths are consumed independently; paired
// releases remain consumed even if Ctrl/Alt were released first.
namespace recoverykeys {
struct Filter {
    bool swallowed[2][2]{};
    bool passed[2][2]{};
    void focus_lost(){*this={};} // Windows/UE release gameplay keys at focus loss.
    bool consume(unsigned channel,UINT key,bool down,bool control,bool alt,bool active) {
        const int index=key=='R'?0:key=='F'?1:-1;
        if(channel>1 || index<0)return false;
        auto& held=swallowed[channel][index];
        auto& delivered=passed[channel][index];
        if(!down){const bool result=held;held=false;delivered=false;return result;}
        if(held)return true;
        if(delivered)return false; // do not swallow a release for a delivered press
        if(active && control && alt){held=true;return true;}
        delivered=true;
        return false;
    }
};
struct Context {
    HWND window=nullptr;WNDPROC previous=nullptr;
    SRWLOCK lock=SRWLOCK_INIT;Filter filter;
    volatile LONG enabled=0;
};
inline constexpr wchar_t PROPERTY[]=L"PBZCoop.RecoveryKeyboard.20261117";
inline Context* current=nullptr; // only the existing poll thread installs/removes
inline volatile LONG ready=0,lastError=ERROR_NOT_READY,stopping=0;
inline volatile LONG routeActive=0;
inline volatile LONG focusEpoch=0;
inline bool key_down(int key){return (GetAsyncKeyState(key)&0x8000)!=0;}
inline bool target_window(HWND window){
    DWORD pid=0;GetWindowThreadProcessId(window,&pid);
    wchar_t name[64]{};
    return pid==GetCurrentProcessId() && GetClassNameW(window,name,64)>0 && wcscmp(name,L"UnrealWindow")==0;
}
inline LRESULT CALLBACK window_proc(HWND window,UINT message,WPARAM wParam,LPARAM lParam){
    auto* context=static_cast<Context*>(GetPropW(window,PROPERTY));
    if(!context || !context->previous)return DefWindowProcW(window,message,wParam,lParam);
    if(message==WM_KILLFOCUS || (message==WM_ACTIVATEAPP && !wParam)){
        AcquireSRWLockExclusive(&context->lock);context->filter.focus_lost();ReleaseSRWLockExclusive(&context->lock);
        InterlockedIncrement(&focusEpoch);
    }
    const bool active=InterlockedCompareExchange(&context->enabled,0,0)!=0 && InterlockedCompareExchange(&routeActive,0,0)!=0 && GetForegroundWindow()==window;
    const bool control=key_down(VK_LCONTROL),alt=key_down(VK_LMENU);
    bool consume=false;
    if(message==WM_KEYDOWN || message==WM_SYSKEYDOWN || message==WM_KEYUP || message==WM_SYSKEYUP){
        const bool down=message==WM_KEYDOWN || message==WM_SYSKEYDOWN;
        AcquireSRWLockExclusive(&context->lock);
        consume=context->filter.consume(0,static_cast<UINT>(wParam),down,control,alt,active);
        ReleaseSRWLockExclusive(&context->lock);
        if(consume)return 0;
    } else if(message==WM_INPUT){
        RAWINPUT input{};UINT bytes=sizeof(input);
        const UINT copied=GetRawInputData(reinterpret_cast<HRAWINPUT>(lParam),RID_INPUT,&input,&bytes,sizeof(RAWINPUTHEADER));
        if(copied!=static_cast<UINT>(-1) && copied>=sizeof(RAWINPUTHEADER)+sizeof(RAWKEYBOARD) && input.header.dwType==RIM_TYPEKEYBOARD){
            AcquireSRWLockExclusive(&context->lock);
            consume=context->filter.consume(1,input.data.keyboard.VKey,(input.data.keyboard.Flags&RI_KEY_BREAK)==0,control,alt,active);
            ReleaseSRWLockExclusive(&context->lock);
            if(consume){DefWindowProcW(window,message,wParam,lParam);return 0;}
        }
    }
    const LRESULT result=CallWindowProcW(context->previous,window,message,wParam,lParam);
    if(message==WM_NCDESTROY){
        InterlockedExchange(&context->enabled,0);InterlockedExchange(&ready,0);
        RemovePropW(window,PROPERTY);
    }
    return result;
}
struct Search {HWND window=nullptr;unsigned matches=0;};
inline BOOL CALLBACK find_window(HWND window,LPARAM parameter){
    auto& search=*reinterpret_cast<Search*>(parameter);
    if(target_window(window)){search.window=window;++search.matches;}return TRUE;
}
inline bool restore(Context* context){
    if(!context)return true;
    InterlockedExchange(&context->enabled,0);InterlockedExchange(&ready,0);
    if(!IsWindow(context->window))return true;
    // Do not destroy another mod's newer subclass chain. Our disabled callback
    // keeps forwarding to the saved previous procedure if still in that chain.
    if(GetWindowLongPtrW(context->window,GWLP_WNDPROC)!=reinterpret_cast<LONG_PTR>(&window_proc))return false;
    SetLastError(0);
    const auto old=SetWindowLongPtrW(context->window,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(context->previous));
    const auto error=GetLastError();
    // The context/property stay alive until the window/process ends: a window
    // callback already in flight may still need its saved previous procedure.
    return old!=0 || error==0;
}
inline bool ensure(){
    if(InterlockedCompareExchange(&stopping,0,0))return false;
    Search search;EnumWindows(find_window,reinterpret_cast<LPARAM>(&search));
    if(search.matches!=1){
        if(current)restore(current);
        InterlockedExchange(&ready,0);InterlockedExchange(&lastError,search.matches?ERROR_DUP_NAME:ERROR_NOT_FOUND);return false;
    }
    if(current && current->window==search.window){
        const bool ok=GetWindowLongPtrW(search.window,GWLP_WNDPROC)==reinterpret_cast<LONG_PTR>(&window_proc);
        InterlockedExchange(&current->enabled,ok);InterlockedExchange(&ready,ok);
        InterlockedExchange(&lastError,ok?ERROR_SUCCESS:ERROR_INVALID_FUNCTION);return ok;
    }
    if(current)restore(current);
    auto* context=new(std::nothrow) Context;
    if(!context){InterlockedExchange(&lastError,ERROR_OUTOFMEMORY);return false;}
    context->window=search.window;
    context->previous=reinterpret_cast<WNDPROC>(GetWindowLongPtrW(search.window,GWLP_WNDPROC));
    if(!context->previous || GetPropW(search.window,PROPERTY) || !SetPropW(search.window,PROPERTY,context)){
        delete context;InterlockedExchange(&ready,0);InterlockedExchange(&lastError,ERROR_INVALID_DATA);return false;
    }
    SetLastError(0);
    const auto previous=SetWindowLongPtrW(search.window,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(&window_proc));
    const auto error=GetLastError();
    if(!previous){
        // WndProc must have a non-null predecessor. Keep the context alive if
        // replacement had any effect, so no in-flight callback can dangle.
        current=context;restore(context);
        InterlockedExchange(&ready,0);InterlockedExchange(&lastError,error?error:ERROR_INVALID_FUNCTION);return false;
    }
    context->previous=reinterpret_cast<WNDPROC>(previous);
    current=context;InterlockedExchange(&context->enabled,1);
    InterlockedExchange(&ready,1);InterlockedExchange(&lastError,0);return true;
}
inline bool available(){return InterlockedCompareExchange(&ready,0,0)!=0;}
inline bool captured(UINT key){
    auto* context=current;const int index=key=='R'?0:key=='F'?1:-1;
    if(!context || index<0 || !available())return false;
    AcquireSRWLockShared(&context->lock);
    const bool result=context->filter.swallowed[0][index] || context->filter.swallowed[1][index];
    ReleaseSRWLockShared(&context->lock);return result;
}
inline void shutdown(){InterlockedExchange(&stopping,1);restore(current);}
inline std::string status(bool controller){
    return "PBZRECHOOK1 "+std::to_string(controller)+" "+std::to_string(available())+" "+std::to_string(InterlockedCompareExchange(&lastError,0,0))+"\n";
}
}
