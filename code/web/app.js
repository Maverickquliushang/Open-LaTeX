'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const title = $('paper-title'), body = $('paper-body');
  const initial = {title: title.value, body: body.value};
  let nextId = 1, versions = [], selectedId;
  const notice = message => { $('notification').textContent = message; };
  const content = () => ({title: title.value, body: body.value});
  const same = (a, b) => a.title === b.title && a.body === b.body;
  const escapeTex = value => value.replace(/[\\{}%$&#_^~]/g, c => ({'\\':'\\textbackslash{}','{':'\\{','}':'\\}','%':'\\%','$':'\\$','&':'\\&','#':'\\#','_':'\\_','^':'\\textasciicircum{}','~':'\\textasciitilde{}'}[c]));
  function source() {
    return '\\documentclass[UTF8]{ctexart}\n\\usepackage{amsmath}\n\\title{' + escapeTex(title.value || '未命名文稿') + '}\n\\author{Open-LaTeX Demo}\n\\date{}\n\\begin{document}\n\\maketitle\n\\section{写作的开始}\n' + body.value.split('\n').map(escapeTex).join('\n\n') + '\n\\[ \\bar{x}=\\frac{1}{n}\\sum_{i=1}^{n}x_i \\]\n\\end{document}\n';
  }
  function addVersion(label, snapshot = content()) {
    const version = {id: nextId++, label, ...snapshot};
    versions.unshift(version);
    versions = versions.slice(0, 20);
    return version;
  }
  function showDiff() {
    const selected = versions.find(v => v.id === selectedId);
    if (!selected) return;
    $('selected-title').textContent = selected.label + ' → 当前内容';
    $('restore-version').disabled = same(selected, content());
    const target = $('diff-view'); target.replaceChildren();
    if (same(selected, content())) {target.textContent = '当前内容与此版本一致。修改正文后，这里会显示差异。'; return;}
    const oldLines = [selected.title, ...selected.body.split('\n')];
    const newLines = [title.value, ...body.value.split('\n')];
    // A line-by-position comparison, deliberately labelled as an illustrative diff.
    for (let i = 0; i < Math.max(oldLines.length, newLines.length); i++) {
      const before = oldLines[i], after = newLines[i];
      const line = (text, type) => {const el = document.createElement('span'); el.className = 'diff-line ' + type; el.textContent = text; target.append(el);};
      if (before === after) {line('  ' + (before || ''), ''); continue;}
      if (before !== undefined) line('− ' + before, 'diff-removed');
      if (after !== undefined) line('+ ' + after, 'diff-added');
    }
  }
  function renderHistory() {
    $('history-count').textContent = `· ${versions.length} 个版本`;
    const list = $('history-list'); list.replaceChildren();
    versions.forEach(v => {
      const button = document.createElement('button'); button.className = 'history-entry' + (v.id === selectedId ? ' active' : '');
      button.setAttribute('aria-pressed', String(v.id === selectedId));
      const label = document.createElement('span'); label.textContent = v.label;
      const number = document.createElement('small'); number.textContent = '#' + String(v.id).padStart(2, '0');
      button.append(label, number); button.addEventListener('click', () => {selectedId = v.id; renderHistory();}); list.append(button);
    });
    showDiff();
  }
  function update() {
    $('preview-title').textContent = title.value || '未命名文稿';
    const preview = $('preview-body'); preview.replaceChildren();
    body.value.split('\n').filter(s => s.trim()).forEach(text => {const p = document.createElement('p'); p.textContent = text; preview.append(p);});
    $('tex-source').textContent = source();
    $('edit-state').textContent = versions[0] && same(versions[0], content()) ? '已记录版本' : '有未记录的修改';
    showDiff();
  }
  title.addEventListener('input', update); body.addEventListener('input', update);
  $('save-version').addEventListener('click', () => {
    const label = $('version-label').value.trim() || '写作版本 ' + nextId;
    const saved = addVersion(label); selectedId = saved.id; $('version-label').value = ''; renderHistory(); update(); notice(`已保存“${label}”。继续修改后，选择旧版本就能比较差异。`);
  });
  $('restore-version').addEventListener('click', () => {
    const target = versions.find(v => v.id === selectedId);
    if (!target || same(target, content())) return;
    addVersion('恢复前备份'); title.value = target.title; body.value = target.body;
    selectedId = addVersion('恢复到：' + target.label).id;
    renderHistory(); update(); notice('已恢复“' + target.label + '”，恢复前内容已保留为一个新版本。');
  });
  $('reset-demo').addEventListener('click', () => {
    if (!window.confirm('重置会清空当前页面内的演示修改和版本。继续吗？')) return;
    title.value = initial.title; body.value = initial.body; versions = []; nextId = 1;
    selectedId = addVersion('初始示例').id; $('version-label').value = ''; renderHistory(); update(); notice('已重置为初始示例。');
  });
  $('download-tex').addEventListener('click', () => {
    const url = URL.createObjectURL(new Blob([source()], {type:'text/plain;charset=utf-8'}));
    const link = document.createElement('a'); link.href = url; link.download = 'main.tex'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000); notice('已下载示例源码。请用 XeLaTeX 编译；网页排版仅作示意。');
  });
  selectedId = addVersion('初始示例').id; renderHistory(); update();
})();
