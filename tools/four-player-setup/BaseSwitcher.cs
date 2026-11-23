using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Drawing;

class BaseFile { public string path;public string sha256; }
class BaseProfile { public string id;public string label;public BaseFile[] files; }
class BaseChange { public string path;public string before;public string after;public string backup; }
class BaseJournal { public string state;public BaseChange[] files; }
static class BaseSwitcher {
 static JavaScriptSerializer json=new JavaScriptSerializer();
 static void CheckBuild(string mod){string exe=Path.GetFullPath(Path.Combine(mod,"..","..","..","PBZ.exe"));if(Hash(exe)!="4415933CE33476F14C837ABB61A1B60AF8B78CD81783896501913A7AAC69E423")throw new Exception("游戏版本不匹配，停止使用固定版本的底座");}
 static bool Allowed(string p){return p=="dlls/main.dll"||(!String.IsNullOrEmpty(p)&&p.StartsWith("Scripts/")&&p.EndsWith(".lua")&&p.Count(c=>c=='/')==1&&!p.Contains("\\"));}
 internal static string Hash(string p){if(!File.Exists(p))return null;using(var s=File.OpenRead(p))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","");}
 static T Read<T>(string p){return json.Deserialize<T>(File.ReadAllText(p,Encoding.UTF8));}
 static void Save(string p,object obj){string temp=p+".tmp";File.WriteAllText(temp,json.Serialize(obj),new UTF8Encoding(false));if(File.Exists(p))File.Replace(temp,p,null);else File.Move(temp,p);}
 static string Safe(string root,string relative){
  if(String.IsNullOrEmpty(relative)||Path.IsPathRooted(relative)||relative.Contains(":")||relative.Split('/','\\').Any(x=>x==".."))throw new Exception("底座路径非法");
  string full=Path.GetFullPath(Path.Combine(root,relative)),basePath=Path.GetFullPath(root).TrimEnd('\\')+"\\";
  if(!full.StartsWith(basePath,StringComparison.OrdinalIgnoreCase))throw new Exception("底座路径越界");
  string check=full;while(!String.IsNullOrEmpty(check)){if((File.Exists(check)||Directory.Exists(check))&&(File.GetAttributes(check)&FileAttributes.ReparsePoint)!=0)throw new Exception("不支持目录联接或符号链接");check=Path.GetDirectoryName(check);}
  return full;
 }
 static BaseProfile Profile(string root,string id){
  if(id!="stable"&&id!="local")throw new Exception("未知底座");
  var p=Read<BaseProfile>(Safe(root,id+"/manifest.json"));
  if(p.id!=id||p.files==null||p.files.Length==0)throw new Exception("底座清单无效");
  var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  foreach(var f in p.files){
   if(!Allowed(f.path)||!seen.Add(f.path))throw new Exception("底座清单越出允许范围");
   if(Hash(Safe(root,id+"/payload/"+f.path))!=f.sha256)throw new Exception("底座文件缺失或损坏："+f.path);
  }return p;
 }
 static bool Matches(string mod,BaseProfile p){return p.files.All(f=>Hash(Safe(mod,f.path))==f.sha256);}
 internal static string Detect(string versions,string mod){
  foreach(string id in new[]{"stable","local"}){var p=Profile(versions,id);if(Matches(mod,p))return p.label;}
  return "文件与已登记版本不一致，暂不可切换";
 }
 internal static string VerifyComponents(string versions,string mod,string[] required){
  foreach(string id in new[]{"stable","local"}){
   var p=Profile(versions,id);
   if(required.All(name=>p.files.Any(f=>f.path==name&&f.sha256!=null))&&Matches(mod,p))return id;
  }
  throw new Exception("AI 组件与两套底座清单均不一致");
 }
 static void Recover(string mod,string journal){
  if(!File.Exists(journal))return;var j=Read<BaseJournal>(journal);
  if(j.state=="committed"||j.state=="rolled_back")return;
  if(j.state!="prepared"||j.files==null||j.files.Length==0||j.files.Any(x=>!Allowed(x.path))||j.files.Select(x=>x.path).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=j.files.Length)throw new Exception("切换恢复记录无效");
  foreach(var x in j.files){var current=Hash(Safe(mod,x.path));if(current!=x.before&&current!=x.after)throw new Exception("切换中断后文件又被修改，保留现场："+x.path);if(x.before!=null&&Hash(Safe(Path.GetDirectoryName(journal),x.backup))!=x.before)throw new Exception("回退备份损坏");}
  foreach(var x in j.files){var target=Safe(mod,x.path);if(x.before!=null)File.Copy(Safe(Path.GetDirectoryName(journal),x.backup),target,true);else if(File.Exists(target))File.Delete(target);}
  j.state="rolled_back";Save(journal,j);
 }
 internal static void Switch(string versions,string mod,string id,bool fixture=false,int failAfter=-1){
  using(var mutex=new Mutex(false,"Local\\PBZLocalBaseSwitch")){
   bool owned=false;try{try{owned=mutex.WaitOne(0);}catch(AbandonedMutexException){owned=true;}if(!owned)throw new Exception("另一底座切换正在进行");
   if(Process.GetProcessesByName("PBZ").Length>0)throw new Exception("请先正常退出游戏，再切换底座");
   if(!fixture)CheckBuild(mod);
   string tx=Safe(mod,"BaseSwitchTransactions");Directory.CreateDirectory(tx);
   foreach(string old in Directory.GetDirectories(tx))Recover(mod,Safe(old,"journal.json"));
   var targetProfile=Profile(versions,id);var stable=Profile(versions,"stable");var local=Profile(versions,"local");
   if(!stable.files.Select(f=>f.path).OrderBy(x=>x).SequenceEqual(local.files.Select(f=>f.path).OrderBy(x=>x)))throw new Exception("两套底座文件清单不配套");
   if(Matches(mod,targetProfile))return;
   if(!Matches(mod,stable)&&!Matches(mod,local))throw new Exception("当前底座被改动，停止切换以保留现状");
   string folder=Safe(tx,DateTime.UtcNow.ToString("yyyyMMddHHmmss")+"-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
   var changes=new List<BaseChange>();int n=0;
   foreach(var f in targetProfile.files){string path=Safe(mod,f.path),before=Hash(path),backup=(n++)+".bak";if(before!=null)File.Copy(path,Safe(folder,backup));changes.Add(new BaseChange{path=f.path,before=before,after=f.sha256,backup=backup});}
   string journal=Safe(folder,"journal.json");var j=new BaseJournal{state="prepared",files=changes.ToArray()};Save(journal,j);
   try{n=0;foreach(var f in targetProfile.files){if(Process.GetProcessesByName("PBZ").Length>0)throw new Exception("游戏在切换期间启动，停止操作");var path=Safe(mod,f.path);if(Hash(path)!=changes[n].before)throw new Exception("文件在切换期间被修改："+f.path);if(f.sha256==null){if(File.Exists(path))File.Delete(path);}else{Directory.CreateDirectory(Path.GetDirectoryName(path));File.Copy(Safe(versions,id+"/payload/"+f.path),path,true);}if(++n==failAfter)throw new Exception("fixture interruption");}
    if(!Matches(mod,targetProfile))throw new Exception("切换后校验失败");j.state="committed";Save(journal,j);
   }catch{if(Process.GetProcessesByName("PBZ").Length==0)Recover(mod,journal);throw;}
  }finally{if(owned)mutex.ReleaseMutex();}}
 }
 internal static void GuardLaunch(string versions,string mod,Action launch,bool fixture=false){
  using(var mutex=new Mutex(false,"Local\\PBZLocalBaseSwitch")){
   bool owned=false;try{
    try{owned=mutex.WaitOne(0);}catch(AbandonedMutexException){owned=true;}
    if(!owned)throw new Exception("底座正在切换，请稍候再启动");
    if(!fixture)CheckBuild(mod);
    string tx=Safe(mod,"BaseSwitchTransactions");
    if(Directory.Exists(tx))foreach(string dir in Directory.GetDirectories(tx)){
     string path=Safe(dir,"journal.json");if(!File.Exists(path))continue;
     var j=Read<BaseJournal>(path);if(j.state!="committed"&&j.state!="rolled_back")throw new Exception("上次切换未完成，请在“选择底座”中重新应用稳定版以恢复");
    }
    if(!Matches(mod,Profile(versions,"stable"))&&!Matches(mod,Profile(versions,"local")))throw new Exception("底座文件不完整或已变动，请先检查底座，未启动游戏");
    launch();
   }finally{if(owned)mutex.ReleaseMutex();}
  }
 }
}
partial class FourPlayerSetup {
 void ChooseBase(){
  if(Preview)return;
  if(Busy){MessageBox.Show(this,"请先正常退出游戏，并等启动流程结束后再切换底座。");return;}
  string versions=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"BaseVersions");
  using(var dialog=new Form{Text="选择底座 · 下次启动生效",Width=600,Height=300,StartPosition=FormStartPosition.CenterParent,Font=Font,BackColor=BackColor,ForeColor=ForeColor}){
   var state=new Label{Left=20,Top=20,Width=540,Height=55};
   try{state.Text="磁盘底座："+BaseSwitcher.Detect(versions,Mod);}catch(Exception ex){state.Text=ex.Message;}
   var pick=new ComboBox{Left=20,Top=82,Width=540,DropDownStyle=ComboBoxStyle.DropDownList};pick.Items.AddRange(new[]{"当前稳定版（1.7.3＋现有补丁）","本地专用测试版 0.1（尚待实机验收）"});pick.SelectedIndex=0;
   var note=new Label{Left=20,Top=125,Width=540,Height=55,Text="需先退出游戏。切换保留绑定、校准和皮肤选择。\n测试版仍复用原游戏适配层；切回底座不会回滚存档。"};
   var apply=new Button{Left=335,Top=192,Width=225,Height=38,Text="应用所选底座",BackColor=Color.SteelBlue,ForeColor=Color.White,FlatStyle=FlatStyle.Flat};
   apply.Click+=(s,e)=>{apply.Enabled=false;try{BaseSwitcher.Switch(versions,Mod,pick.SelectedIndex==0?"stable":"local");state.Text="已切换："+BaseSwitcher.Detect(versions,Mod)+"\n下次启动生效，运行效果待验证。";}catch(Exception ex){MessageBox.Show(dialog,ex.Message,"未完成切换");}finally{apply.Enabled=true;}};
   dialog.Controls.AddRange(new Control[]{state,pick,note,apply});dialog.ShowDialog(this);
  }
 }
}
