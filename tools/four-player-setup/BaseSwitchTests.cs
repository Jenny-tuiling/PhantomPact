using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
class BaseSwitchTests {
 static int count;
 static void Check(bool b,string label){if(!b)throw new Exception(label);count++;}
 static void Fails(Action a,string label){bool failed=false;try{a();}catch{failed=true;}Check(failed,label);}
 static void Json(string p,object x){File.WriteAllText(p,new JavaScriptSerializer().Serialize(x));}
 static void Put(string p,string text){Directory.CreateDirectory(Path.GetDirectoryName(p));File.WriteAllText(p,text);}
 static void Main(){
  string root=Path.Combine(Path.GetTempPath(),"PBZBaseFixture-"+Guid.NewGuid().ToString("N"));
  string mod=Path.Combine(root,"mod"),versions=Path.Combine(root,"versions");
  string[] files={"dlls/main.dll","Scripts/main.lua","Scripts/local_lifecycle.lua"};
  foreach(string id in new[]{"stable","local"}){
   var manifest=new BaseProfile{id=id,label=id,files=files.Select((p,i)=>{
    string payloadFile=Path.Combine(versions,id,"payload",p);if(id!="stable"||i!=2)Put(payloadFile,id+" fixture "+i);
    return new BaseFile{path=p,sha256=BaseSwitcher.Hash(payloadFile)};
   }).ToArray()};Json(Path.Combine(versions,id,"manifest.json"),manifest);
  }
  foreach(var p in files.Take(2))Put(Path.Combine(mod,p),File.ReadAllText(Path.Combine(versions,"stable","payload",p)));
  string config=Path.Combine(mod,"four_bindings.txt");Put(config,"4 1 3 2 personal");
  Check(BaseSwitcher.Detect(versions,mod)=="stable","stable detected");
  BaseSwitcher.Switch(versions,mod,"local",true);
  Check(BaseSwitcher.Detect(versions,mod)=="local","local installed");
  Check(BaseSwitcher.VerifyComponents(versions,mod,files)=="local","candidate components verified");
  Fails(()=>BaseSwitcher.VerifyComponents(versions,mod,new[]{"Scripts/missing.lua"}),"missing required component refused");
  Check(File.ReadAllText(config)=="4 1 3 2 personal","bindings preserved");
  bool launch=false;BaseSwitcher.GuardLaunch(versions,mod,()=>launch=true,true);Check(launch,"complete candidate can launch");
  BaseSwitcher.Switch(versions,mod,"stable",true);
  Check(BaseSwitcher.Detect(versions,mod)=="stable","rollback matches stable");
  Check(!File.Exists(Path.Combine(mod,files[2])),"new Lua removed on rollback");
  Fails(()=>BaseSwitcher.Switch(versions,mod,"local",true,1),"injected copy failure");
  Check(BaseSwitcher.Detect(versions,mod)=="stable","automatic rollback after copy failure");
  string payload=Path.Combine(versions,"local","payload",files[0]);string original=File.ReadAllText(payload);
  File.AppendAllText(payload,"corrupt");Fails(()=>BaseSwitcher.Switch(versions,mod,"local",true),"damaged payload rejected");File.WriteAllText(payload,original);
  string targetMain=Path.Combine(mod,files[1]);File.AppendAllText(targetMain,"external change");
  Fails(()=>BaseSwitcher.Switch(versions,mod,"local",true),"unknown modified base rejected");
  Fails(()=>BaseSwitcher.GuardLaunch(versions,mod,()=>{},true),"unknown base cannot launch");
  File.Copy(Path.Combine(versions,"stable","payload",files[1]),targetMain,true);
  Fails(()=>BaseSwitcher.Switch(versions,mod,"local"),"real game build guard");
  Fails(()=>BaseSwitcher.GuardLaunch(versions,mod,()=>{}),"real launch build guard");
  string tx=Path.Combine(mod,"BaseSwitchTransactions","interrupted");Directory.CreateDirectory(tx);
  string target=Path.Combine(mod,files[0]);File.Copy(target,Path.Combine(tx,"0.bak"));
  string before=BaseSwitcher.Hash(target);File.Copy(payload,target,true);
  Json(Path.Combine(tx,"journal.json"),new BaseJournal{state="prepared",files=new[]{new BaseChange{path=files[0],before=before,after=BaseSwitcher.Hash(target),backup="0.bak"}}});
  Fails(()=>BaseSwitcher.GuardLaunch(versions,mod,()=>{},true),"pending transaction blocks launch");
  BaseSwitcher.Switch(versions,mod,"stable",true);Check(BaseSwitcher.Detect(versions,mod)=="stable","restart recovers interrupted transaction");
  string manifestPath=Path.Combine(versions,"local","manifest.json"),oldManifest=File.ReadAllText(manifestPath);
  Json(manifestPath,new BaseProfile{id="local",files=new[]{new BaseFile{path="Scripts/../../escape.lua"}}});
  Fails(()=>BaseSwitcher.Switch(versions,mod,"local",true),"traversal rejected");File.WriteAllText(manifestPath,oldManifest);
  Check(File.ReadAllText(config)=="4 1 3 2 personal","bindings still intact after failures");
  Console.WriteLine("BaseSwitchTests: "+count+" passed; isolated fixture "+root);
 }
}
