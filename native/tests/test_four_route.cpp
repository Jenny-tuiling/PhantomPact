#include "four_route.hpp"
#include <cassert>
#include <cstring>
#include <iostream>
BYTE players[4][0x120]{};
int expected=0;
ULONG_PTR mock_input(void*,BYTE*,void*,void*) {
    for(int i=0;i<4;i++) {
        const auto id=*reinterpret_cast<int*>(players[i]+0xE0);
        const auto user=*reinterpret_cast<int*>(players[i]+0x104);
        assert(id==(i>=fourroute::binding.count?i:i==expected?0:16+i));
        assert(user==(i>=fourroute::binding.count?i:i==expected?0:16+i));
    }
    return 123;
}
int main() {
    BYTE event[64]{};
    for(int i=0;i<4;i++) {
        fourroute::binding.player[i]=reinterpret_cast<unsigned long long>(players[i]);
        *reinterpret_cast<int*>(players[i]+0xE0)=i;
        *reinterpret_cast<int*>(players[i]+0x104)=i;
    }
    fourroute::binding.updated=GetTickCount64();
    for(expected=0;expected<4;expected++) {
        *reinterpret_cast<int*>(event+0x0C)=expected+1;
        ULONG_PTR result=0;
        assert(fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));
        assert(result==123);
        for(int i=0;i<4;i++) {
            assert(*reinterpret_cast<int*>(players[i]+0xE0)==i);
            assert(*reinterpret_cast<int*>(players[i]+0x104)==i);
        }
    }
    ULONG_PTR result=0;
    fourroute::binding.device[3]=-1;
    *reinterpret_cast<int*>(event+0x0C)=4;
    assert(fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));
    assert(result==1); // disconnected/unassigned pad is consumed, never player 1
    expected=0;
    *reinterpret_cast<int*>(event+0x0C)=0;
    assert(fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));
    assert(result==123);
    for(int i=0;i<4;i++) fourroute::binding.device[i]=4-i;
    for(expected=0;expected<4;expected++) {
        *reinterpret_cast<int*>(event+0x0C)=4-expected;
        assert(fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));
        assert(result==123);
    }
    for(int count=2;count<=3;count++) {
        fourroute::binding.count=count;
        for(int i=0;i<4;i++) {
            fourroute::binding.player[i]=i<count?reinterpret_cast<unsigned long long>(players[i]):0;
            fourroute::binding.device[i]=i<count?i+1:-1;
        }
        for(expected=0;expected<count;expected++) {
            *reinterpret_cast<int*>(event+0x0C)=expected+1;
            assert(fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));assert(result==123);
        }
        *reinterpret_cast<int*>(event+0x0C)=count+1;
        assert(fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));assert(result==1);
    }
    fourroute::binding.updated=0;
    assert(!fourroute::dispatch(mock_input,nullptr,event,nullptr,nullptr,&result));
    std::cout<<"PASS: four device routes, reassignment, disconnected pad blocked, keyboard, state restored, disabled state\n";
}
