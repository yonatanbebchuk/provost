"""Build and verify the portable developer ZIP without repository imports."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent
FILES = ['__init__.py','scenario.json','environment.py','evaluator.py','server.py',
         'run_demo.py','test_demo.py','README.md','build_package.py']


def build():
    dist = ROOT/'dist'; dist.mkdir(exist_ok=True)
    archive = dist/'banking-loans-standalone.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name in FILES:
            info = zipfile.ZipInfo('banking_loans/'+name, date_time=(2026,1,1,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info,(ROOT/name).read_bytes())
    with tempfile.TemporaryDirectory(prefix='banking-demo-check-',dir=ROOT) as temporary:
        if not Path(temporary).resolve().is_relative_to(ROOT.resolve()):
            raise ValueError('Verification directory must stay within package directory')
        with zipfile.ZipFile(archive) as z:
            z.extractall(temporary)
        standalone = Path(temporary)/'banking_loans'
        subprocess.run([sys.executable,'-I','-m','unittest','discover','-s',str(standalone),'-p','test_demo.py'],cwd=standalone,check=True)
        subprocess.run([sys.executable,'run_demo.py','--output','runs/portable-check'],cwd=standalone,check=True)
        requests = '\n'.join(json.dumps(x) for x in [
            {'op':'reset'},{'op':'step','action':{'action':'read_context'}},
            {'op':'step','action':{'action':'quote','apr_bps':650,'commitment':'indicative','disclose':True}},
            {'op':'step','action':{'action':'finish'}}])+'\n'
        process = subprocess.run([sys.executable,'server.py'],input=requests,text=True,capture_output=True,cwd=standalone,check=True)
        responses = [json.loads(line) for line in process.stdout.splitlines()]
        assert len(responses)==4 and all(r['ok'] for r in responses)
        assert responses[-1]['result']['reward']==60 and responses[-1]['result']['done']
    manifest = {'archive':archive.name,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
                'files':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in FILES},
                'verified_from_extracted_directory':True,'tests':10,'constructed_controls':16,
                'json_lines_smoke_passed':True,'dependencies':'Python 3.10+ standard library only',
                'scope':'Developer/coordinator package; not an isolated learner filesystem'}
    (dist/'checksums.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps({'archive':archive.name,'verified':True,'sha256':manifest['sha256']},indent=2))


if __name__=='__main__':
    build()
