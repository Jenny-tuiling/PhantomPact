#pragma once
#include <windows.h>
#include <Xinput.h>
#include <array>
#include <cstdio>
#include <share.h>
#include <sstream>
#include <string>

// Local input producer protocol. All access is protected by partyinput::mutex.
// Logical slots are 1..4 externally, 0..3 internally. Slot 0 never accepts AI.
namespace partyai {
constexpr ULONGLONG HOLD_MS=4000, FRESH_MS=750, WATCHDOG_MS=1500;
constexpr BYTE TRIGGER_ON=128, TRIGGER_OFF=32;
constexpr WORD GAMEPLAY_BUTTONS=0xF38F; // DPAD, R3, LB/RB, ABXY; no L3/Start/Back
enum Reason { Normal=0, Watchdog=1, Disconnected=2, BindingLost=3, FocusLost=4 };

struct Hold {
    bool armed=false, trigger=false, consumed=false, timing=false;
    ULONGLONG start=0;
    bool update(bool stick,BYTE rt,ULONGLONG now) {
        if(rt>=TRIGGER_ON)trigger=true; else if(rt<=TRIGGER_OFF)trigger=false;
        if(!stick && !trigger) {armed=true;consumed=false;timing=false;return false;}
        if(stick && trigger) {
            consumed=true;
            if(!armed)return false;
            if(!timing){timing=true;start=now;}
            if(now-start>=HOLD_MS){armed=false;timing=false;return true;}
        } else timing=false;
        return false;
    }
};
struct Frame {
    unsigned slot=0; unsigned long long epoch=0; bool allow=false;
    XINPUT_GAMEPAD pad{};
};
struct Packet {
    unsigned long long session=0, sequence=0;
    std::array<Frame,3> frame{};
};
inline bool parse(const std::string& text,Packet& packet) {
    if(text.empty() || text.size()>2048)return false;
    Packet next; std::istringstream in(text); std::string magic;long long session,sequence;
    if(!(in>>magic>>session>>sequence) || magic!="PBZAI1" || session<=0 || sequence<=0)return false;
    next.session=session;next.sequence=sequence;
    unsigned seen=0;
    for(auto& f:next.frame) {
        long long slot,epoch,allow,buttons,lt,rt,lx,ly,rx,ry;
        if(!(in>>slot>>epoch>>allow>>buttons>>lt>>rt>>lx>>ly>>rx>>ry))return false;
        if(slot<2 || slot>4 || epoch<1 || (seen&(1u<<slot)) || (allow!=0 && allow!=1))return false;
        if(buttons<0 || buttons>65535 || (buttons&~GAMEPLAY_BUTTONS) || lt<0 || lt>255 || rt<0 || rt>255)return false;
        if(lx< -32768 || lx>32767 || ly< -32768 || ly>32767 || rx< -32768 || rx>32767 || ry< -32768 || ry>32767)return false;
        seen|=1u<<slot;f.slot=static_cast<unsigned>(slot);f.epoch=epoch;f.allow=allow!=0;
        f.pad={static_cast<WORD>(buttons),static_cast<BYTE>(lt),static_cast<BYTE>(rt),
            static_cast<SHORT>(lx),static_cast<SHORT>(ly),static_cast<SHORT>(rx),static_cast<SHORT>(ry)};
    }
    std::string extra;if(in>>extra)return false;
    packet=next;return seen==28;
}
struct Mode {
    // enabled is the user's requested AI mode (PBZAI1 enabled), not proof of output.
    // Only allow + a current-epoch fresh packet may produce actual gameplay input.
    bool enabled=false, allow=false, received=false, handoffPending=false;
    unsigned long long epoch=1, identity=0;
    int device=-1, reason=Normal;
    ULONGLONG changed=0, receivedAt=0;
    XINPUT_GAMEPAD pad{};
    Hold hold;
};
struct Control {
    unsigned long long session, acceptedSequence=0;
    bool focused=true;
    Mode mode[4];
    explicit Control(unsigned long long value):session(value){}
    void stop(unsigned slot,int why,ULONGLONG now,bool resetHold=true) {
        if(slot==0 || slot>=4)return;
        // AI intent belongs to the logical seat for this game process. Only
        // the user's explicit off chord (Normal) may cancel it. Disconnect,
        // reassignment, missing routes and focus loss merely suspend output.
        if(why!=Normal){suspend(slot,why,now,resetHold);return;}
        auto& m=mode[slot];
        if(m.enabled)m.handoffPending=true;
        if(m.enabled || m.received){++m.epoch;m.changed=now;}
        m.enabled=false;m.allow=false;m.received=false;m.pad={};m.reason=why;
        if(resetHold)m.hold={};
    }
    // Death, loading and a rebuilt LocalPlayer invalidate output, not user intent.
    void suspend(unsigned slot,int why,ULONGLONG now,bool resetHold=true) {
        if(slot==0 || slot>=4)return;
        auto& m=mode[slot];
        if(m.enabled && (m.received || m.allow))m.handoffPending=true;
        if(m.received || m.allow){++m.epoch;m.changed=now;}
        m.allow=false;m.received=false;m.pad={};m.reason=why;
        if(resetHold)m.hold={};
    }
    // Focus changes pause output, not the user's selected companion mode.
    // Invalidate both edges: packets generated while backgrounded cannot be
    // replayed when returning to gameplay, even if their timestamp is fresh.
    void focus(bool active,ULONGLONG now) {
        if(active==focused)return;
        focused=active;
        for(unsigned slot=1;slot<4;slot++) {
            auto& m=mode[slot];const auto before=m.epoch;
            suspend(slot,FocusLost,now);
            if(m.epoch==before){++m.epoch;m.changed=now;}
        }
    }
    void bind(unsigned slot,int device,unsigned long long identity,bool valid,ULONGLONG now,bool transientRoute=false) {
        if(slot==0 || slot>=4)return;
        auto& m=mode[slot];
        if(!valid || device<1 || device>4 || !identity) {
            if(transientRoute){
                const auto oldEpoch=m.epoch;
                const bool hadIdentity=m.identity!=0;
                suspend(slot,BindingLost,now,hadIdentity);
                if(hadIdentity && m.epoch==oldEpoch){++m.epoch;m.changed=now;}
                // Retain the physical slot so its raw off chord and unplug check
                // still work while localfour temporarily publishes zero routes.
                m.identity=0;return;
            }
            stop(slot,BindingLost,now);m.device=-1;m.identity=0;return;
        }
        if(m.device!=device || m.identity!=identity){
            const auto oldEpoch=m.epoch;
            if(m.device==device)suspend(slot,BindingLost,now);
            else stop(slot,BindingLost,now); // retain seat intent, invalidate old-device output
            if(m.epoch==oldEpoch){++m.epoch;m.changed=now;}
            m.device=device;m.identity=identity;
        }
    }
    bool accept(const Packet& packet,ULONGLONG now) {
        if(!focused || packet.session!=session || packet.sequence<=acceptedSequence)return false;
        acceptedSequence=packet.sequence;
        for(const auto& f:packet.frame) {
            if(f.slot<2 || f.slot>4)continue;
            auto& m=mode[f.slot-1];
            if(f.epoch!=m.epoch || m.device<1 || !m.identity)continue;
            m.received=true;m.receivedAt=now;m.allow=f.allow;m.pad=f.allow?f.pad:XINPUT_GAMEPAD{};
            if(f.allow)m.reason=Normal;
        }
        return true;
    }
    bool fresh(unsigned slot,ULONGLONG now)const {
        const auto& m=mode[slot];return m.received && now-m.receivedAt<=FRESH_MS;
    }
    bool raw(unsigned slot,const XINPUT_GAMEPAD& pad,ULONGLONG now,bool allowEnable=true) {
        if(!focused || slot==0 || slot>=4)return false;
        auto& m=mode[slot];
        if(!m.hold.update((pad.wButtons&XINPUT_GAMEPAD_LEFT_THUMB)!=0,pad.bRightTrigger,now))return false;
        if(m.enabled){stop(slot,Normal,now,false);return true;}
        if(!allowEnable || !fresh(slot,now) || !m.allow || m.device<1 || !m.identity)return false;
        m.enabled=true;m.handoffPending=true;++m.epoch;m.changed=now;m.received=false;m.allow=false;m.pad={};m.reason=Normal;
        return true;
    }
    unsigned long long uiSequence[4]{};
    bool request(const std::string& text,ULONGLONG now,bool allowEnable) {
        if(text.size()>256)return false;
        std::istringstream in(text);std::string magic,extra;
        unsigned long long sid,seq,epoch;int slot,on;
        if(!(in>>magic>>sid>>seq>>slot>>epoch>>on) || in>>extra)return false;
        if(magic!="PBZAISET1" || sid!=session || !seq || slot<2 || slot>4 || (on!=0 && on!=1))return false;
        unsigned i=slot-1;auto& m=mode[i];
        if(seq<=uiSequence[i])return false;
        uiSequence[i]=seq;
        if(epoch!=m.epoch)return false;
        if(!on){stop(i,Normal,now,false);return true;}
        if(!allowEnable || m.device<1 || !m.identity)return false;
        if(!m.enabled){m.enabled=true;m.handoffPending=true;++m.epoch;m.changed=now;m.received=false;m.allow=false;m.pad={};m.reason=focused?Watchdog:FocusLost;}
        return true;
    }
    void watchdog(ULONGLONG now) {
        for(unsigned slot=1;slot<4;slot++) {
            auto& m=mode[slot];
            if(m.enabled && now-(m.received?m.receivedAt:m.changed)>WATCHDOG_MS)suspend(slot,Watchdog,now,false);
        }
    }
    XINPUT_GAMEPAD output(unsigned slot,ULONGLONG now)const {
        const auto& m=mode[slot];
        return focused && m.enabled && m.allow && fresh(slot,now)?m.pad:XINPUT_GAMEPAD{};
    }
    std::string status(bool installed)const {
        std::ostringstream out;out<<"PBZAI1 "<<session<<' '<<installed<<' '<<acceptedSequence<<'\n';
        for(unsigned s=1;s<4;s++)out<<s+1<<' '<<mode[s].enabled<<' '<<mode[s].epoch<<' '<<mode[s].reason<<'\n';
        return out.str();
    }
};
// Lua publishes this small packet concurrently. UCRT _wfopen_s uses _SH_SECURE
// and a read handle denies writers; share both read and write instead. A torn
// read is still rejected by the unchanged complete-record parser below.
inline FILE* open_packet(const std::wstring& path) {
    return _wfsopen(path.c_str(),L"rb",_SH_DENYNO);
}
inline bool read(const std::wstring& path,Packet& packet) {
    FILE* f=open_packet(path);if(!f)return false;
    char text[2049];const auto size=fread(text,1,sizeof(text),f);fclose(f);
    if(size==sizeof(text))return false;
    return parse(std::string(text,size),packet);
}
} // namespace partyai
