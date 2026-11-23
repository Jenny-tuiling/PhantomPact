using System.Drawing;
using System.Windows.Forms;

partial class FourPlayerSetup {
    void InitializeShortcutHelp(){
        Panel panel=new Panel{BackColor=Color.FromArgb(35,43,57),BorderStyle=BorderStyle.FixedSingle};
        panel.SetBounds(30,786,695,436);Controls.Add(panel);
        Label heading=new Label{Text="自定义快捷键 · 多人模式内使用",ForeColor=Color.FromArgb(255,227,157),Font=new Font(Font.FontFamily,15,FontStyle.Bold)};
        heading.SetBounds(14,10,665,30);panel.Controls.Add(heading);
        string[] rows={
            "2～4号 · AI托管    L3 ＋ RT 按住4秒：切换真人／AI",
            "2～4号 · 自己归队  L3 ＋ R3 按住3秒：回到1号身边",
            "1号手柄 · 锁定    L3 ＋ RT 按住3秒：锁定／解锁队友",
            "1号键盘 · 锁定／解锁  左Ctrl ＋ 左Shift ＋ Z 按住2秒",
            "所有玩家手柄 · 恢复自己视角  R3 ＋ 方向键↓ 按住2秒",
            "1号手柄 · 安全脱困  L3 ＋ R3 按住3秒",
            "1号手柄 · 全队召回  R3 ＋ LT 按住3秒：逐个召回队友",
            "1号键盘 · 恢复视角  左Ctrl ＋ 左Alt ＋ R 按住2秒",
            "1号键盘 · 安全脱困  左Ctrl ＋ 左Alt ＋ F 按住3秒"
        };
        for(int i=0;i<rows.Length;i++){
            Label row=new Label{Text=rows[i],ForeColor=Color.White,Font=new Font(Font.FontFamily,12,FontStyle.Bold)};
            row.SetBounds(14,48+i*30,665,28);panel.Controls.Add(row);
        }
        Label legend=new Label{Text="L3 = 左摇杆按下；R3 = 右摇杆按下",ForeColor=Color.MediumAquamarine,Font=new Font(Font.FontFamily,11,FontStyle.Bold)};
        legend.SetBounds(14,323,665,27);panel.Controls.Add(legend);
        Label triggers=new Label{Text="LT = 左扳机；RT = 右扳机",ForeColor=Color.MediumAquamarine,Font=new Font(Font.FontFamily,11,FontStyle.Bold)};
        triggers.SetBounds(14,350,665,27);panel.Controls.Add(triggers);
        Label directions=new Label{Text="↓ = 方向键下，不是推动摇杆",ForeColor=Color.MediumAquamarine,Font=new Font(Font.FontFamily,11,FontStyle.Bold)};
        directions.SetBounds(14,377,665,27);panel.Controls.Add(directions);
        Label note=new Label{Text="组合键须同时按住；触发后松开，再按可再次触发。",ForeColor=Color.Silver};
        note.SetBounds(14,405,665,24);panel.Controls.Add(note);
    }
}
