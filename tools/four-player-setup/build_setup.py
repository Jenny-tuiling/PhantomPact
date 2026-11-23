"""Build maintained launcher sources, including the independent recovery request UI."""
from pathlib import Path
import argparse
import os
import subprocess

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=root/'四人设备设置.exe')
parser.add_argument('--test', action='store_true')
args = parser.parse_args()
compiler = Path(os.environ.get('WINDIR', r'C:\Windows'))/'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
sources = [root/name for name in ('FourPlayerSetup.cs','AiCompanion.cs','ShortcutHelp.cs','RecoveryUi.cs','TempPowerUi.cs','CompactUi.cs','BaseSwitcher.cs','AssemblyInfo.cs')]
for source in sources:
    if not source.is_file():
        raise SystemExit('Required maintained source missing: '+str(source))
output = args.output.resolve()
output.parent.mkdir(parents=True,exist_ok=True)
framework = compiler.parent
references = ('mscorlib.dll','System.dll','System.Core.dll','System.Drawing.dll',
              'System.Windows.Forms.dll','System.Web.Extensions.dll')
common = [str(compiler),'/nologo','/noconfig','/nostdlib+','/platform:x64','/codepage:65001']
common += ['/reference:'+str(framework/name) for name in references]
subprocess.run(common+['/target:winexe','/out:'+str(output)]+[str(p) for p in sources],check=True)
if args.test:
    for name in ('LauncherTests','RecoveryTests','AiReadOnlyTests','ShortcutContractTests','TempPowerTests','BaseSwitchTests'):
        test_source=root/(name+'.cs')
        test_output=output.parent/(name+'.exe')
        subprocess.run(common+['/target:exe','/main:'+name,'/out:'+str(test_output)]
                       +[str(p) for p in sources]+[str(test_source)],check=True)
        subprocess.run([str(test_output)],check=True)
print('Built: '+str(output))
