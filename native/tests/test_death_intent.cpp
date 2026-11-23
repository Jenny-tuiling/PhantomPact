#define NOMINMAX
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"

static unsigned checks=0;
#define CHECK(x) do { ++checks; if(!(x))throw std::runtime_error(#x); } while(0)
using namespace partyai;
XINPUT_GAMEPAD chord(){XINPUT_GAMEPAD p{};p.wButtons=XINPUT_GAMEPAD_LEFT_THUMB;p.bRightTrigger=255;return p;}
bool zero(const XINPUT_GAMEPAD& p){const XINPUT_GAMEPAD n{};return std::memcmp(&p,&n,sizeof(p))==0;}
Packet makePacket(unsigned long long sequence,bool allow=true){
    auto& c=partyinput::ai;Packet p;p.session=c.session;p.sequence=sequence;
    for(unsigned i=0;i<3;i++)p.frame[i]={i+2,c.mode[i+1].epoch,allow,{XINPUT_GAMEPAD_A,0,0,12000,8000,0,0}};
    return p;
}
fourroute::Binding route(ULONGLONG now=100){
    fourroute::Binding b;b.updated=now;b.count=4;
    for(unsigned i=0;i<4;i++){b.player[i]=1000+i;b.device[i]=i+1;}return b;
}
fourroute::Binding unroute(ULONGLONG now){
    auto b=route(now);for(unsigned i=0;i<4;i++){b.player[i]=0;b.device[i]=-1;}return b;
}
void reset(){partyinput::ai=Control{99};partyinput::locked=false;}
ULONGLONG enable(unsigned slot,ULONGLONG now,unsigned long long& seq){
    auto& c=partyinput::ai;c.raw(slot,{},now);c.raw(slot,chord(),now+1);
    c.accept(makePacket(++seq),now+HOLD_MS);CHECK(c.raw(slot,chord(),now+HOLD_MS+1));CHECK(c.mode[slot].enabled);
    c.accept(makePacket(++seq),now+HOLD_MS+2);CHECK(!zero(c.output(slot,now+HOLD_MS+2)));return now+HOLD_MS+2;
}
int main(){
    using namespace partyinput;
    for(unsigned seat=1;seat<4;seat++){
        reset();unsigned long long seq=0;auto b=route();bind_ai(b,100);auto now=enable(seat,100,seq);
        const auto before=makePacket(++seq);const auto epoch=ai.mode[seat].epoch;
        auto none=unroute(now+1);bind_ai(none,now+1);
        CHECK(ai.mode[seat].enabled);CHECK(ai.mode[seat].device==int(seat+1));CHECK(ai.mode[seat].identity==0);
        CHECK(ai.mode[seat].epoch>epoch);CHECK(zero(ai.output(seat,now+1)));
        ai.accept(before,now+2);CHECK(!ai.mode[seat].received);CHECK(zero(ai.output(seat,now+2)));
        b.updated=now+3;b.player[seat]+=10000;bind_ai(b,now+3);
        CHECK(ai.mode[seat].enabled);CHECK(zero(ai.output(seat,now+3)));
        ai.accept(makePacket(++seq,false),now+4);CHECK(ai.mode[seat].enabled && zero(ai.output(seat,now+4)));
        ai.accept(makePacket(++seq),now+5);CHECK(!zero(ai.output(seat,now+5)));
        CHECK(ai.status(true).find(std::to_string(seat+1)+" 1 ")!=std::string::npos);
        const auto stale=makePacket(++seq);ai.watchdog(now+5+WATCHDOG_MS+1);
        CHECK(ai.mode[seat].enabled && ai.mode[seat].reason==Watchdog);CHECK(zero(ai.output(seat,now+5+WATCHDOG_MS+1)));
        const auto pausedEpoch=ai.mode[seat].epoch;
        for(unsigned repeat=0;repeat<40;repeat++){ai.watchdog(now+5+WATCHDOG_MS+1+repeat*50);CHECK(ai.mode[seat].epoch==pausedEpoch);}
        ai.accept(stale,now+5+WATCHDOG_MS+2);CHECK(!ai.mode[seat].received);
        ai.accept(makePacket(++seq),now+5+WATCHDOG_MS+3);CHECK(!zero(ai.output(seat,now+5+WATCHDOG_MS+3)));
    }
    // Manual off must work during a long empty route and cannot be resurrected.
    reset();unsigned long long seq=0;auto b=route();bind_ai(b,100);auto now=enable(1,100,seq);
    auto none=unroute(now+1);bind_ai(none,now+1);ai.raw(1,{},now+2);
    ai.raw(1,chord(),now+3);
    for(ULONGLONG dt=100;dt<HOLD_MS;dt+=100){none.updated=now+3+dt;bind_ai(none,none.updated);CHECK(!ai.raw(1,chord(),none.updated));}
    none.updated=now+3+HOLD_MS;bind_ai(none,none.updated);CHECK(ai.raw(1,chord(),none.updated));CHECK(!ai.mode[1].enabled);
    b.updated=none.updated+1;b.player[1]+=10000;bind_ai(b,b.updated);ai.accept(makePacket(++seq),b.updated+1);
    CHECK(!ai.mode[1].enabled && zero(ai.output(1,b.updated+1)));
    // Intent belongs to the logical seat even while its device or route is unavailable.
    reset();seq=0;b=route();bind_ai(b,100);now=enable(1,100,seq);b.updated=now+1;b.device[1]=4;b.device[3]=2;bind_ai(b,now+1);CHECK(ai.mode[1].enabled && zero(ai.output(1,now+1)));
    reset();seq=0;b=route();bind_ai(b,100);now=enable(3,100,seq);b.count=3;b.updated=now+1;bind_ai(b,now+1);CHECK(ai.mode[3].enabled && zero(ai.output(3,now+1)));
    reset();seq=0;b=route();bind_ai(b,100);now=enable(1,100,seq);b.device[1]=-1;b.updated=now+1;bind_ai(b,now+1);CHECK(ai.mode[1].enabled && zero(ai.output(1,now+1)));
    reset();seq=0;b=route();bind_ai(b,100);now=enable(1,100,seq);b.device[1]=3;b.updated=now+1;bind_ai(b,now+1);CHECK(ai.mode[1].enabled && zero(ai.output(1,now+1)));
    // Existing genuine disconnect/focus shutdown and P1 exclusion remain.
    for(int reason:{Disconnected,FocusLost}){
        reset();seq=0;b=route();bind_ai(b,100);now=enable(1,100,seq);auto stale=makePacket(++seq);ai.stop(1,reason,now+1);
        ai.accept(stale,now+2);CHECK(ai.mode[1].enabled && zero(ai.output(1,now+2)));
        ai.accept(makePacket(++seq),now+3);CHECK(ai.mode[1].enabled && !zero(ai.output(1,now+3)));
    }
    ai.bind(0,1,1000,true,100);ai.suspend(0,BindingLost,100);ai.raw(0,{},100);CHECK(!ai.raw(0,chord(),10000));CHECK(!ai.mode[0].enabled);
    // A stale route is a pause, but never authorizes a stale packet or output.
    reset();seq=0;b=route();bind_ai(b,100);now=enable(2,100,seq);b.updated=now;bind_ai(b,now+1600);
    CHECK(ai.mode[2].enabled && ai.mode[2].identity==0 && zero(ai.output(2,now+1600)));
    std::cout<<"death_intent: "<<checks<<" checks passed\n";
}
