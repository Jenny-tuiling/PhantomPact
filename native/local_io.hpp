#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>
#include <iterator>
#include <initializer_list>
namespace localio {
inline double monotonic(){return GetTickCount64()/1000.0;}
inline void write_atomic(const std::wstring& path,const std::string& text){
 auto temp=path+L".localtmp";FILE* f=nullptr;
 if(_wfopen_s(&f,temp.c_str(),L"wb")!=0||!f)return;
 bool ok=fwrite(text.data(),1,text.size(),f)==text.size();if(fclose(f)!=0)ok=false;
 if(ok)MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
inline void append_lines(const std::wstring& path,std::initializer_list<std::string> lines){
 FILE* f=nullptr;if(_wfopen_s(&f,path.c_str(),L"ab")!=0||!f)return;
 for(auto& s:lines){fwrite(s.data(),1,s.size(),f);fwrite("\n",1,1,f);}fclose(f);
}
}
