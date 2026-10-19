(() => {
  const vscode = acquireVsCodeApi(), $ = id => document.getElementById(id);
  let sequence = 0, generation = 0, detailGeneration = 0, contentGeneration = 0;
  let versions = [], selected, file = '', content, files = [], tab = 'diff', busy = false;
  const pending = new Map();
  function request(action, extra = {}) {
    return new Promise((resolve,reject) => {const id = ++sequence; pending.set(id,{resolve,reject});
      vscode.postMessage({id,action,project:$('project').value,...extra});});
  }
  window.addEventListener('message', event => {const r = event.data, p = pending.get(r.id); if (!p) return;
    pending.delete(r.id); r.error ? p.reject(new Error(r.error)) : p.resolve(r.data);});
  function notice(text, error = false) {$('notice').textContent = text; $('notice').classList.toggle('error',error);}
  function fail(e) {notice(e.message,true);}
  function el(tag,text,cls) {const node=document.createElement(tag); if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;}
  const title = v => v.label || v.message.replace(/ · \d{4}-.*$/,'').replace(/^里程碑：/,'');
  const date = v => new Date(v.date).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false});
  function controls() {
    $('snapshot').disabled=busy||!$('project').value;
    $('restore').disabled=$('rename').disabled=busy||!selected;
    $('project').disabled=$('refresh').disabled=busy;
    $('native').disabled=busy||!content||content.binary;
  }
  function renderVersions() {
    const search=$('search').value.toLowerCase(); $('versions').replaceChildren(); let previous='';
    for(const v of versions) {
      if(!(title(v)+' '+date(v)).toLowerCase().includes(search))continue;
      const day=new Date(v.date).toLocaleDateString('zh-CN',{timeZone:'Asia/Shanghai'});
      if(day!==previous){$('versions').append(el('div',day,'day'));previous=day;}
      const button=el('button',undefined,'version'+(v.sha===selected?.sha?' active':''));button.disabled=busy;
      button.append(el('small',date(v).split(' ')[1]||date(v)),el('strong',title(v)),el('small',v.sha.slice(0,8)));
      button.onclick=()=>selectVersion(v).catch(fail);$('versions').append(button);
    }
    $('count').textContent=versions.length+' 条';
  }
  function renderFiles() {
    $('files').replaceChildren();
    const shown=files.filter(f=>!$('onlyChanged').checked||f.changed);
    for(const f of shown){const b=el('button',undefined,'file'+(file===f.path?' active':''));b.disabled=busy;
      b.append(el('span',f.path),el('small',f.status));b.onclick=()=>selectFile(f.path).catch(fail);$('files').append(b);}
    if(!shown.length)$('files').append(el('p','这个版本与当前已保存内容一致。','muted'));
  }
  function renderContent() {
    for(const key of ['diff','old','current'])$(key+'Tab').setAttribute('aria-selected',String(tab===key));
    $('content').replaceChildren();$('stats').textContent='';
    if(!content){$('content').append(el('p','请选择文件。','empty'));return;}
    if(content.binary){$('content').append(el('p',content.reason,'empty'));return;}
    if(tab==='old'||tab==='current') {
      $('content').append(el('pre',tab==='old'?content.before:content.after));
      if(!(tab==='old'?content.oldExists:content.currentExists))$('content').append(el('p',tab==='old'?'这个文件在所选版本中还不存在。':'这个文件当前已删除。','empty'));
    } else if(!content.diff) $('content').append(el('p','这个文件与当前已保存内容相同。点击“历史全文”可阅读当时的完整内容。','empty'));
    else {
      $('stats').textContent='当前相对历史：+'+content.additions+' / −'+content.deletions;
      const fragment=document.createDocumentFragment();
      for(const line of content.diff.split('\n'))fragment.append(el('div',line,'diffline '+(line.startsWith('@@')?'hunk':line.startsWith('+')?'add':line.startsWith('-')?'remove':'')));
      $('content').append(fragment);
    }
  }
  async function selectFile(name) {
    const token=++contentGeneration;file=name;content=null;$('filename').textContent=name;renderFiles();renderContent();controls();
    const result=await request('content',{sha:selected.sha,file:name});
    if(token!==contentGeneration)return;content=result;renderContent();controls();
  }
  async function selectVersion(v) {
    const token=++detailGeneration;++contentGeneration;selected=v;file='';content=null;files=[];
    $('title').textContent=title(v);$('date').textContent=date(v)+' · 查看不会改变当前论文';
    $('filename').textContent='请选择文件';renderVersions();renderFiles();renderContent();controls();
    notice('正在对比所选版本与当前已保存内容…');
    const data=await request('details',{sha:v.sha});if(token!==detailGeneration)return;
    files=data.files;renderFiles();const changed=files.filter(f=>f.changed);
    notice(changed.length?`${changed.length} 个文件与当前不同。红色是历史内容，绿色是当前内容。`:'这个版本与当前已保存内容一致，可以直接查看历史全文。');
    const first=changed.find(f=>f.path.endsWith('.tex'))||files.find(f=>f.path.endsWith('.tex'))||files[0];
    if(first)await selectFile(first.path);
  }
  async function load(append=false,keep=false) {
    const token=++generation, old=keep?selected?.sha:undefined;
    if(!append){++detailGeneration;++contentGeneration;versions=[];selected=null;files=[];content=null;file='';renderVersions();renderFiles();renderContent();controls();}
    notice('正在读取历史版本…');
    const data=await request('history',{offset:append?versions.length:0});if(token!==generation)return;
    versions=append?versions.concat(data.versions):data.versions;
    $('more').hidden=!data.more;$('saved').textContent=data.dirty?'有修改等待下一次记录':'当前内容已记录';renderVersions();
    if(!append&&versions.length)await selectVersion(versions.find(v=>v.sha===old)||versions[0]);
    else notice(append?'已加载更早版本。':'尚无历史记录。');
    vscode.setState({project:$('project').value});controls();
  }
  async function mutate(action) {
    if(busy)return;const v=selected;busy=true;controls();renderVersions();renderFiles();
    try {
      const result=await request(action,{sha:v?.sha,title:v?title(v)+' · '+date(v):'',label:action==='rename'?(v?.label||''):''});
      if(!result.cancelled){await load(false,action==='rename');notice(action==='restore'?'已恢复；“恢复前备份”保留了原内容。请重新编译 PDF。':action==='snapshot'?'命名版本已保存。':'版本名称已更新。');}
    }catch(e){fail(e);}finally{busy=false;controls();renderVersions();renderFiles();}
  }
  $('project').onchange=()=>load().catch(fail);$('refresh').onclick=()=>load(false,true).catch(fail);
  $('search').oninput=renderVersions;$('onlyChanged').onchange=renderFiles;
  $('more').onclick=()=>load(true).catch(fail);
  for(const action of ['snapshot','rename','restore'])$(action).onclick=()=>mutate(action);
  for(const key of ['diff','old','current'])$(key+'Tab').onclick=()=>{tab=key;renderContent();};
  $('native').onclick=()=>request('diff',{sha:selected.sha,file}).catch(fail);
  request('init').then(async data=>{
    for(const p of data.projects){const option=el('option',p.name);option.value=p.name;$('project').append(option);}
    const preferred=data.preferred||vscode.getState()?.project;
    if(data.projects.some(p=>p.name===preferred))$('project').value=preferred;
    if(data.projects.length)await load();else{notice('papers 下还没有已启用历史的论文。');controls();}
  }).catch(fail);
})();
