using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

// Preview-only UI inspection. No game start, recovery requests or device input.
class ShortcutContractTests {
    static int checks;
    static void Check(bool value,string description){checks++;if(!value)throw new Exception(description);}
    static IEnumerable<Label> Labels(Control root){
        foreach(Control child in root.Controls){
            Label label=child as Label;if(label!=null)yield return label;
            foreach(Label nested in Labels(child))yield return nested;
        }
    }
    [STAThread] static void Main(){
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        using(FourPlayerSetup form=new FourPlayerSetup(true)){
            Label[] labels=Labels(form).ToArray();
            foreach(string expected in new[]{
                "1号手柄 · 锁定    L3 ＋ RT 按住3秒",
                "1号手柄 · 安全脱困  L3 ＋ R3 按住3秒",
                "1号手柄 · 全队召回  R3 ＋ LT 按住3秒",
                "2～4号 · 自己归队  L3 ＋ R3 按住3秒",
                "2～4号 · AI托管    L3 ＋ RT 按住4秒",
                "1号键盘 · 锁定／解锁  左Ctrl ＋ 左Shift ＋ Z 按住2秒",
                "所有玩家手柄 · 恢复自己视角  R3 ＋ 方向键↓ 按住2秒",
                "1号键盘 · 恢复视角  左Ctrl ＋ 左Alt ＋ R 按住2秒",
                "1号键盘 · 安全脱困  左Ctrl ＋ 左Alt ＋ F 按住3秒"
            })Check(labels.Any(l=>l.Text.Contains(expected)&&l.Font.Bold),"Bold current binding: "+expected);
            Check(!labels.Any(l=>l.Text.Contains("锁定    L3 ＋ R3")),"Old host lock instruction removed");
            Check(!labels.Any(l=>l.Text.Contains("安全脱困  R3 ＋ 方向键↑")),"Old safe instruction removed");
            MethodInfo build=typeof(FourPlayerSetup).GetMethod("BuildRecoveryPanel",BindingFlags.Instance|BindingFlags.NonPublic);
            using(Form panel=(Form)build.Invoke(form,null)){
                Label line=Labels(panel).Single(l=>l.Text.Contains("1号手柄："));
                Check(line.Text.Contains("1号手柄：L3 ＋ R3 按住3秒，安全脱困。")&&line.Font.Bold,"Recovery dialog has bold new safe binding");
                Check(line.Text.Contains("R3 ＋ 方向键↓ 按住2秒"),"Camera shortcut retained");
                Check(line.Text.Contains("R3 ＋ LT 按住3秒")&&line.Font.Bold,"Bold host whole-party recall in recovery panel");
                Check(line.Text.Contains("左Ctrl ＋ 左Alt ＋ R 按住2秒")&&line.Text.Contains("左Ctrl ＋ 左Alt ＋ F 按住3秒"),"Keyboard recovery shortcuts retained");
                Check(line.Text.Contains("L3 = 左摇杆按下；R3 = 右摇杆按下"),"Stick press explained");
                Check(Labels(panel).Any(l=>l.Text.Contains("行走或站立满1秒")&&l.Text.Contains("无法执行时会提示原因")),"Grounded recording and refusal explained");
            }
            using(Form aiPanel=(Form)typeof(FourPlayerSetup).GetMethod("BuildAiPanel",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(form,null)){
                Check(Labels(aiPanel).Any(l=>l.Text.Contains("仅主动关闭或重启游戏才退出托管。")&&l.Font.Bold),"AI lifecycle explained in bold");
                Check(Labels(aiPanel).Any(l=>l.Text.Contains("自动安全归队")&&l.Text.Contains("红色“AI托管中”")&&l.Font.Bold),"Automatic regroup and red AI banner explained");
            }
            Check(typeof(FourPlayerSetup).GetMethod("UpgradeAi",BindingFlags.Instance|BindingFlags.NonPublic)==null,"Read-only AI launcher capability retained");
        }
        Console.WriteLine("Shortcut contract: "+checks+" checks passed");
    }
}
