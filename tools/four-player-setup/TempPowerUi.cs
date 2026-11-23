using System;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public sealed class TempPowerState {
    public string Session,State,Accepted;
    public int Players,Applied;
}
public static class TempPowerFiles {
    public static bool Parse(string text,out TempPowerState state){
        state=null;if(text==null || text.Length>256)return false;
        Match m=Regex.Match(text,@"\APBZPOWER1 ([a-zA-Z0-9-]{1,80}) (off|on|waiting|error) ([0-4]) ([0-4]) ([a-zA-Z0-9-]{1,80})\r?\n?\z");
        if(!m.Success)return false;
        state=new TempPowerState{Session=m.Groups[1].Value,State=m.Groups[2].Value,Players=int.Parse(m.Groups[3].Value),Applied=int.Parse(m.Groups[4].Value),Accepted=m.Groups[5].Value};
        return state.Applied<=state.Players;
    }
    public static bool Read(string directory,DateTime gameStart,out TempPowerState state){
        state=null;
        try{
            string file=Path.Combine(directory,"status.txt");FileInfo info=new FileInfo(file);
            if(!info.Exists || info.Length>256 || info.LastWriteTimeUtc<gameStart)return false;
            double age=(DateTime.UtcNow-info.LastWriteTimeUtc).TotalSeconds;
            if(age < -0.5 || age > 4)return false;
            using(FileStream stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
            using(StreamReader reader=new StreamReader(stream,Encoding.ASCII)){
                char[] buffer=new char[257];int length=reader.ReadBlock(buffer,0,buffer.Length);
                return length<=256 && Parse(new string(buffer,0,length),out state);
            }
        }catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}
    }
    public static string Submit(string directory,TempPowerState state,bool enabled){
        if(state==null || !Regex.IsMatch(state.Session??"",@"\A[a-zA-Z0-9-]{1,80}\z"))throw new ArgumentException("Invalid current session");
        string id=Guid.NewGuid().ToString("N"),target=Path.Combine(directory,"request.txt"),temp=target+"."+id+".tmp";
        try{
            File.WriteAllText(temp,"PBZPOWER1 "+state.Session+" "+id+" "+(enabled?"on":"off")+"\n",Encoding.ASCII);
            if(File.Exists(target))File.Replace(temp,target,null);else File.Move(temp,target);
        }finally{if(File.Exists(temp))File.Delete(temp);}
        return id;
    }
}
partial class FourPlayerSetup {
    Button tempPowerButton=new Button();Label tempPowerStatus=new Label();
    DateTime nextTempPowerCheck,tempPowerSentAt;string tempPowerPending="",tempPowerPendingSession="";TempPowerState tempPowerState;
    string TempPowerDirectory{get{return Path.Combine(Path.GetDirectoryName(Mod.TrimEnd('\\','/')),"PBZPartyPower");}}
    void InitializeTempPowerUi(){
        Panel panel=new Panel{BackColor=Color.FromArgb(35,43,57)};panel.SetBounds(745,904,305,260);Controls.Add(panel);
        Label title=new Label{Text="临时增强 · 全体玩家",Font=new Font(Font.FontFamily,14,FontStyle.Bold),ForeColor=Color.FromArgb(255,227,157)};
        title.SetBounds(12,12,281,30);panel.Controls.Add(title);
        tempPowerButton.Text="开启无敌 ＋ 10倍伤害";tempPowerButton.Font=new Font(Font.FontFamily,12,FontStyle.Bold);
        tempPowerButton.SetBounds(12,50,281,56);tempPowerButton.FlatStyle=FlatStyle.Flat;tempPowerButton.ForeColor=Color.White;tempPowerButton.BackColor=Color.FromArgb(49,114,91);
        tempPowerButton.Click+=(s,e)=>ToggleTempPower();panel.Controls.Add(tempPowerButton);
        tempPowerStatus.Text="默认关闭 · 进入多人存档后可开启";tempPowerStatus.ForeColor=Color.Silver;tempPowerStatus.SetBounds(12,116,281,56);panel.Controls.Add(tempPowerStatus);
        Label note=new Label{Text="对所有已加入的玩家生效。\n再次点击恢复正常数值。\n仅本次游戏有效，重启后默认关闭。",ForeColor=Color.Silver};note.SetBounds(12,177,281,74);panel.Controls.Add(note);
        tempPowerButton.Enabled=false;
    }
    void RefreshTempPowerUi(){
        if(DateTime.UtcNow<nextTempPowerCheck)return;nextTempPowerCheck=DateTime.UtcNow.AddMilliseconds(500);
        if(Preview){tempPowerStatus.Text="预览：默认关闭 · 全员无敌＋10倍伤害";return;}
        bool fresh=gameStarted && TempPowerFiles.Read(TempPowerDirectory,gameStartUtc,out tempPowerState);
        if(!fresh){if(!gameStarted)tempPowerPending="";tempPowerButton.Enabled=false;tempPowerButton.Text="开启无敌 ＋ 10倍伤害";tempPowerStatus.Text=gameStarted?"等待临时增强组件就绪…":"默认关闭 · 进入多人存档后可开启";return;}
        bool timedOut=tempPowerPending.Length>0 && (DateTime.UtcNow-tempPowerSentAt).TotalSeconds>10;
        if(tempPowerPendingSession!=tempPowerState.Session || timedOut)tempPowerPending="";
        if(tempPowerPending==tempPowerState.Accepted)tempPowerPending="";
        bool on=tempPowerState.State=="on" || tempPowerState.State=="waiting";
        tempPowerButton.Enabled=tempPowerPending.Length==0 && (on || tempPowerState.Players>=2);
        tempPowerButton.Text=on?"关闭增强 · 恢复正常":"开启无敌 ＋ 10倍伤害";
        tempPowerButton.BackColor=on?Color.FromArgb(153,56,53):Color.FromArgb(49,114,91);
        tempPowerStatus.ForeColor=on?Color.LightGreen:Color.Silver;
        tempPowerStatus.Text=timedOut?"未收到游戏确认；可根据当前状态重试。":tempPowerPending.Length>0?"请求已发送，等待游戏确认…":tempPowerState.State=="error"?"应用失败，已停止；请查看游戏日志。":on?"已开启 · "+tempPowerState.Applied+" / "+tempPowerState.Players+" 人生效\n复活、切图后自动继续应用。":"已关闭 · 正常生命与伤害";
    }
    void ToggleTempPower(){
        if(Preview)return;
        try{
            TempPowerState current;
            if(!gameStarted || !TempPowerFiles.Read(TempPowerDirectory,gameStartUtc,out current))throw new InvalidOperationException("游戏组件尚未就绪，请先进入多人存档。");
            bool on=current.State=="on" || current.State=="waiting";
            if(!on && current.Players<2)throw new InvalidOperationException("此按钮仅用于多人模式。");
            tempPowerPending=TempPowerFiles.Submit(TempPowerDirectory,current,!on);tempPowerPendingSession=current.Session;tempPowerSentAt=DateTime.UtcNow;tempPowerButton.Enabled=false;
            tempPowerStatus.Text="请求已发送，等待游戏确认…";
        }catch(Exception e){MessageBox.Show(this,e.Message,"临时增强",MessageBoxButtons.OK,MessageBoxIcon.Information);}
    }
}
