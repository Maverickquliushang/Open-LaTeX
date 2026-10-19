'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const original = {
    'main.tex': String.raw`% !TeX program = xelatex
\documentclass[UTF8,a4paper,11pt]{ctexart}
\usepackage[margin=25mm]{geometry}
\usepackage{amsmath}
\title{从第一行开始}
\author{Open-LaTeX 示例}
\date{}

\begin{document}
\maketitle

\begin{abstract}
一个清楚、安静的写作起点。
用这个小例子体验编辑、编译与版本回看。
\end{abstract}

\input{sections/intro}

\section{一个简单的公式}
对一组观测值，算术平均值为：
\begin{equation}
  \bar{x} = \frac{1}{n}\sum_{i=1}^{n}x_i.
\end{equation}

% 如需书目，请在真实 TeX 环境中取消注释：
% \bibliographystyle{plain}
% \bibliography{references}
\end{document}
`,
    'sections/intro.tex': String.raw`\section{写作的开始}
研究的开始，往往只是一个值得追问的小问题。

把复杂的工具留在容器里，把写作的节奏留给自己。
修改、保存、回看，每一步都清楚可循。

\section{保留思路的来路}
在重要修改前记下一个版本。
即使后来走了弯路，也能找回当时的思路。
`,
    'references.bib': String.raw`% 原创演示书目，仅用于展示 .bib 文件结构。
% 不是实际发表的论文，请勿用于正式引用。
@misc{openlatexDemo,
  author = {{Open-LaTeX contributors}},
  title  = {Open-LaTeX 示例文稿},
  year   = {2026},
  note   = {Fictional example; do not cite}
}
`
  };
  let files = {...original}, active = 'main.tex', versions = [], nextId = 1, selectedId;
  const editor = $('source-editor');
  const notice = message => {$('notification').textContent = message;};
  const equal = (a,b) => Object.keys(original).every(name => a[name] === b[name]);
  const commitEdit = () => {files[active] = editor.value;};
  const stripComments = text => text.split('\n').map(line => line.replace(/(?<!\\)%.*/, '')).join('\n');
  const plain = text => text.replace(/\\(?:textbf|textit|emph|texttt)\{([^{}]*)\}/g,'$1').replace(/\\([%&#_$])/g,'$1').replace(/\$([^$]*)\$/g,'$1').replace(/\\(?:LaTeX|TeX)\b/g,'LaTeX');
  function braces(text, command) {
    const at=text.indexOf('\\'+command+'{'); if(at<0)return '';
    const start=at+command.length+2;let depth=1;
    for(let i=start;i<text.length;i++){if(text[i]==='{'&&text[i-1]!=='\\')depth++;if(text[i]==='}'&&text[i-1]!=='\\')depth--;if(!depth)return text.slice(start,i);}
    return '';
  }
  function renderTree() {
    const list=$('file-list');list.replaceChildren();
    Object.keys(files).forEach(name => {
      const button=document.createElement('button');button.className='file-entry'+(name===active?' active':'')+(name.includes('/')?' nested':'');
      button.textContent=(name.endsWith('.bib')?'B  ':'T  ')+name;button.setAttribute('aria-pressed',String(name===active));
      button.addEventListener('click',()=>{commitEdit();active=name;editor.value=files[name];$('active-filename').textContent=name;renderTree();lineNumbers();editor.scrollTop=0;editor.scrollLeft=0;});list.append(button);
    });
  }
  function lineNumbers() {
    $('line-numbers').textContent=editor.value.split('\n').map((_,i)=>i+1).join('\n');
    $('line-numbers').scrollTop=editor.scrollTop;
    $('source-position').textContent=(active.endsWith('.bib')?'BibTeX':'LaTeX')+' · '+editor.value.split('\n').length+' 行 · UTF-8';
    $('edit-state').textContent=versions[0]&&equal(versions[0].files,files)?'已记录版本':'有未记录修改';
  }
  function preview() {
    commitEdit();const warnings=[];let tex=stripComments(files['main.tex']);
    let seen=new Set(['main.tex']);
    function expand(text, depth=0) {
      if(depth>5){warnings.push('嵌套层数超过演示范围。');return '';}
      return text.replace(/\\input\{([^{}]+)\}/g,(_,name)=>{const path=name.endsWith('.tex')?name:name+'.tex';if(!Object.hasOwn(files,path)){warnings.push('找不到文件：'+path);return '';}
        if(seen.has(path)){warnings.push('检测到循环引用：'+path);return '';}
        seen.add(path);const value=expand(stripComments(files[path]),depth+1);seen.delete(path);return value;});
    }
    tex=expand(tex);
    if(!tex.includes('\\begin{document}')||!tex.includes('\\end{document}'))warnings.push('缺少 document 起止标记；请检查主文件。');
    $('preview-title').textContent=plain(braces(tex,'title'))||'未命名文稿';
    $('preview-author').textContent=plain(braces(tex,'author'))||'Open-LaTeX 示例';
    let content=tex.split('\\begin{document}')[1]?.split('\\end{document}')[0]||'';
    const target=$('preview-body');target.replaceChildren();let section=0,paragraph=[];
    const flush=()=>{if(paragraph.length){const p=document.createElement('p');p.textContent=plain(paragraph.join(' '));target.append(p);paragraph=[];}};
    const lines=content.split('\n');
    for(let i=0;i<lines.length;i++){
      const line=lines[i].trim();
      if(!line){flush();continue;}
      if(line==='\\maketitle')continue;
      if(line.startsWith('\\section{')){flush();const h=document.createElement('h4');h.textContent=(++section)+'  '+plain(braces(line,'section'));target.append(h);continue;}
      if(line==='\\begin{abstract}'){
        flush();let text=[];while(++i<lines.length&&!lines[i].includes('\\end{abstract}'))text.push(lines[i]);
        const box=document.createElement('div');box.className='paper-abstract';const h=document.createElement('h4');h.textContent='摘要';const p=document.createElement('p');p.textContent=plain(text.join(' '));box.append(h,p);target.append(box);continue;
      }
      if(line==='\\begin{equation}'){
        flush();let math=[];while(++i<lines.length&&!lines[i].includes('\\end{equation}'))math.push(lines[i]);
        const formula=math.join(' ').trim();const block=document.createElement('div');block.className='equation';
        if(formula.replace(/\s/g,'')===String.raw`\bar{x}=\frac{1}{n}\sum_{i=1}^{n}x_i.`){
          // Fixed trusted MathML for the included example; never interpolate editor text into HTML.
          block.innerHTML='<math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><mrow><mover><mi>x</mi><mo>¯</mo></mover><mo>=</mo><mfrac><mn>1</mn><mi>n</mi></mfrac><munderover><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><msub><mi>x</mi><mi>i</mi></msub></mrow></math>';
        }else{block.className='formula-source';block.textContent=formula;warnings.push('自定义公式以源码显示；完整排版请使用 TeX 编译。');}target.append(block);continue;
      }
      if(/\\(?:cite\w*|bibliography|bibliographystyle|includegraphics|begin)\b/.test(line))warnings.push('包含示例预览不支持的引用、图片或环境，请在 TeX 中编译。');
      if(/\\(?!textbf\b|textit\b|emph\b|texttt\b|LaTeX\b|TeX\b|[%&#_$])[a-zA-Z]+/.test(line))warnings.push('部分 LaTeX 命令在演示中按源码显示。');
      paragraph.push(line);
    }
    flush();$('preview-warning').textContent=[...new Set(warnings)].join(' ');$('preview-state').textContent='已更新 · 浏览器示意，非 PDF';notice(warnings.length?'预览已更新；请查看预览区提示。':'已根据 main.tex 与正文文件更新预览。');
  }
  function addVersion(label){const v={id:nextId++,label,files:{...files}};versions.unshift(v);versions=versions.slice(0,20);return v;}
  function diff(){
    const v=versions.find(x=>x.id===selectedId);if(!v)return;
    $('selected-title').textContent=v.label+' → 当前项目';$('restore-version').disabled=equal(v.files,files);
    const out=$('diff-view');out.replaceChildren();if(equal(v.files,files)){out.textContent='当前项目与此版本一致。编辑源码后可在这里比较差异。';return;}
    const append=(text,style)=>{const el=document.createElement('span');el.className='diff-line '+style;el.textContent=text;out.append(el);};
    Object.keys(files).forEach(name=>{if(v.files[name]===files[name])return;append(name,'diff-file');const old=v.files[name].split('\n'),now=files[name].split('\n');for(let i=0;i<Math.max(old.length,now.length);i++){if(old[i]===now[i])continue;if(old[i]!==undefined)append('− '+old[i],'diff-removed');if(now[i]!==undefined)append('+ '+now[i],'diff-added');}});
  }
  function history(){
    $('history-count').textContent='· '+versions.length+' 个版本';const list=$('history-list');list.replaceChildren();
    versions.forEach(v=>{const b=document.createElement('button');b.className='history-entry'+(v.id===selectedId?' active':'');b.setAttribute('aria-pressed',String(v.id===selectedId));const label=document.createElement('span');label.textContent=v.label;const n=document.createElement('small');n.textContent='#'+String(v.id).padStart(2,'0');b.append(label,n);b.addEventListener('click',()=>{selectedId=v.id;history();});list.append(b);});diff();lineNumbers();
  }
  editor.addEventListener('input',()=>{commitEdit();lineNumbers();diff();$('preview-state').textContent='源码已修改 · 点击更新预览';});
  editor.addEventListener('scroll',()=>{$('line-numbers').scrollTop=editor.scrollTop;});
  editor.addEventListener('keydown',event=>{if(event.key==='Tab'){event.preventDefault();editor.setRangeText('  ',editor.selectionStart,editor.selectionEnd,'end');editor.dispatchEvent(new Event('input'));}});
  $('update-preview').addEventListener('click',preview);
  $('save-version').addEventListener('click',()=>{commitEdit();const label=$('version-label').value.trim()||'写作版本 '+nextId;selectedId=addVersion(label).id;$('version-label').value='';history();notice('已保存项目版本“'+label+'”，包含全部三个文件。');});
  $('restore-version').addEventListener('click',()=>{commitEdit();const target=versions.find(v=>v.id===selectedId);if(!target||equal(target.files,files))return;addVersion('恢复前备份');files={...target.files};selectedId=addVersion('恢复到：'+target.label).id;editor.value=files[active];history();preview();notice('已恢复全部示例文件，并保留“恢复前备份”。');});
  $('reset-demo').addEventListener('click',()=>{if(!confirm('重置会清空当前页面的源码修改和版本。继续吗？'))return;files={...original};active='main.tex';versions=[];nextId=1;selectedId=addVersion('初始示例').id;editor.value=files[active];$('active-filename').textContent=active;renderTree();history();preview();notice('已重置演示项目。');});
  $('download-tex').addEventListener('click',()=>{commitEdit();const url=URL.createObjectURL(new Blob([files[active]],{type:'text/plain;charset=utf-8'}));const link=document.createElement('a');link.href=url;link.download=active.split('/').pop();link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);notice('已下载 '+active+'。完整编译需下载全部文件并保持 sections/intro.tex 目录结构。');});
  editor.value=files[active];selectedId=addVersion('初始示例').id;renderTree();history();preview();
})();
