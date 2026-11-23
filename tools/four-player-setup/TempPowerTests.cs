using System;
using System.IO;
using System.Text;
public class TempPowerTests {
 static int n;static void Check(bool v){if(!v)throw new Exception("TempPower check "+n);n++;}
 public static void Main(){
  TempPowerState s;
  Check(TempPowerFiles.Parse("PBZPOWER1 abc-1 off 4 0 none\n",out s));Check(s.State=="off");
  foreach(string bad in new[]{"","PBZPOWER1 a on 2 4 x","PBZPOWER1 a on 5 5 x","PBZPOWER1 a on 4 4 x\non","PBZPOWER1 ../a off 4 0 x","PBZPOWER1 a execute 4 0 x"})Check(!TempPowerFiles.Parse(bad,out s));
  string dir=Path.Combine(Path.GetTempPath(),"PBZ-PowerTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
  try{
   Check(TempPowerFiles.Parse("PBZPOWER1 session-1 on 4 4 none\n",out s));
   string first=TempPowerFiles.Submit(dir,s,false);Check(File.ReadAllText(Path.Combine(dir,"request.txt")).Contains(" "+first+" off"));
   string second=TempPowerFiles.Submit(dir,s,true);Check(second!=first);Check(File.ReadAllText(Path.Combine(dir,"request.txt")).Contains(" "+second+" on"));
   string status=Path.Combine(dir,"status.txt");File.WriteAllText(status,"PBZPOWER1 session-1 on 4 4 "+second+"\n",Encoding.ASCII);
   Check(TempPowerFiles.Read(dir,DateTime.UtcNow.AddSeconds(-1),out s));
   using(FileStream writer=new FileStream(status,FileMode.Open,FileAccess.ReadWrite,FileShare.ReadWrite|FileShare.Delete)){
    Check(TempPowerFiles.Read(dir,DateTime.UtcNow.AddSeconds(-1),out s));
    Check(s.State=="on");
   }
   File.WriteAllText(status,new string('x',257),Encoding.ASCII);
   Check(!TempPowerFiles.Read(dir,DateTime.UtcNow.AddSeconds(-1),out s));
   File.WriteAllText(status,"PBZPOWER1 session-1 on 4 4 "+second+"\n",Encoding.ASCII);
   File.SetLastWriteTimeUtc(status,DateTime.UtcNow.AddSeconds(-8));Check(!TempPowerFiles.Read(dir,DateTime.UtcNow.AddSeconds(-10),out s));
   File.SetLastWriteTimeUtc(status,DateTime.UtcNow);Check(!TempPowerFiles.Read(dir,DateTime.UtcNow.AddMinutes(1),out s));
  }finally{foreach(string f in Directory.GetFiles(dir))File.Delete(f);Directory.Delete(dir);}
  Console.WriteLine("Temporary power UI: "+n+" checks passed");
 }
}
