#define NOMINMAX
#include <iostream>
#include <stdexcept>
#include <cstring>
#include "party_ai.hpp"
static int checks=0;
#define CHECK(x) do {++checks;if(!(x))throw std::runtime_error(#x);}while(0)
using namespace partyai;
bool zero(XINPUT_GAMEPAD p){XINPUT_GAMEPAD n{};return std::memcmp(&p,&n,sizeof(p))==0;}
Packet packet(Control& c,unsigned long long seq){Packet p;p.session=c.session;p.sequence=seq;for(int i=0;i<3;i++)p.frame[i]={unsigned(i+2),c.mode[i+1].epoch,true,{XINPUT_GAMEPAD_A,0,0,12000,0,0,0}};return p;}
XINPUT_GAMEPAD chord(){XINPUT_GAMEPAD p{};p.wButtons=XINPUT_GAMEPAD_LEFT_THUMB;p.bRightTrigger=255;return p;}
int main(){
 for(unsigned slot=1;slot<4;slot++){
  Control c{55};ULONGLONG now=100;unsigned long long seq=0;
  c.bind(slot,int(slot+1),100+slot,true,now);
  c.raw(slot,{},now);c.raw(slot,chord(),now+1);now+=4001;c.accept(packet(c,++seq),now);CHECK(c.raw(slot,chord(),now));CHECK(c.mode[slot].enabled);
  c.raw(slot,{},++now);
  for(int repeat=0;repeat<100;repeat++){
   c.accept(packet(c,++seq),++now);auto stale=packet(c,++seq);
   c.bind(slot,-1,0,false,++now);CHECK(c.mode[slot].enabled);CHECK(zero(c.output(slot,now)));
   c.accept(stale,++now);CHECK(zero(c.output(slot,now)));
   // A different physical pad resumes the same logical player's selected mode.
   c.bind(slot,repeat%4+1,2000+repeat,true,++now);CHECK(c.mode[slot].enabled);
   c.accept(packet(c,++seq),++now);CHECK(!zero(c.output(slot,now)));
   for(int reason:{Disconnected,BindingLost,Watchdog}){
    stale=packet(c,++seq);c.stop(slot,reason,++now);CHECK(c.mode[slot].enabled&&zero(c.output(slot,now)));
    c.accept(stale,++now);CHECK(zero(c.output(slot,now)));
    c.accept(packet(c,++seq),++now);CHECK(!zero(c.output(slot,now)));
   }
   c.focus(false,++now);CHECK(c.mode[slot].enabled);auto bg=packet(c,++seq);CHECK(!c.accept(bg,++now));CHECK(zero(c.output(slot,now)));
   c.focus(true,++now);c.accept(bg,++now);CHECK(zero(c.output(slot,now)));c.accept(packet(c,++seq),++now);CHECK(!zero(c.output(slot,now)));
  }
  // Manual off remains authoritative across subsequent recoveries.
  c.raw(slot,{},++now);c.raw(slot,chord(),++now);now+=4000;CHECK(c.raw(slot,chord(),now));CHECK(!c.mode[slot].enabled);
  for(int reason:{Disconnected,BindingLost,FocusLost,Watchdog}){c.stop(slot,reason,++now);c.accept(packet(c,++seq),++now);CHECK(!c.mode[slot].enabled&&zero(c.output(slot,now)));}
  Control restart{56};CHECK(!restart.mode[slot].enabled);CHECK(!restart.accept(packet(c,++seq),++now));CHECK(zero(restart.output(slot,now)));
  CHECK(!c.mode[0].enabled);
 }
 std::cout<<"ai_session: "<<checks<<" checks passed\n";
}
