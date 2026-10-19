const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const {spawn} = require('child_process');
const crypto = require('crypto');

function activate(context) {
  let panel, mutation = false;
  const virtual = new Map();
  const findRoot = () => {
    for (const folder of vscode.workspace.workspaceFolders || []) {
      let current = folder.uri.fsPath;
      for (let i = 0; i < 8; i++) {
        if (fs.existsSync(path.join(current, '.latex-tools', 'paper_history.py'))) return current;
        const parent = path.dirname(current); if (parent === current) break; current = parent;
      }
    }
    throw new Error('请在连接 latex 容器的 VS Code 窗口中打开论文工作区。');
  };
  const api = request => new Promise((resolve, reject) => {
    let root; try {root = findRoot();} catch(e) {reject(e); return;}
    const child = spawn('python3', [path.join(context.extensionPath, 'backend.py')], {stdio: ['pipe','pipe','pipe']});
    let output = '', error = '';
    const timer = setTimeout(() => {child.kill(); reject(new Error('历史操作超时，请刷新后检查结果。'));}, 240000);
    child.stdout.on('data', chunk => {output += chunk; if (output.length > 16000000) child.kill();});
    child.stderr.on('data', chunk => {error += chunk;});
    child.on('error', e => {clearTimeout(timer); reject(e);});
    child.on('close', () => {
      clearTimeout(timer);
      try {const result = JSON.parse(output); result.ok ? resolve(result.data) : reject(new Error(result.error));}
      catch(e) {reject(new Error(error || '无法读取历史记录：' + e.message));}
    });
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify({...request, root}));
  });
  const savePaper = async project => {
    const dir = path.join(findRoot(), 'papers', project) + path.sep;
    for (const doc of vscode.workspace.textDocuments) {
      if (doc.uri.scheme === 'file' && doc.uri.fsPath.startsWith(dir) && doc.isDirty) {
        if (!await doc.save()) throw new Error('文件尚未保存，操作已取消。');
      }
    }
  };
  const selectedPaper = () => {
    try {
      const file = vscode.window.activeTextEditor?.document.uri.fsPath;
      const relative = file && path.relative(path.join(findRoot(), 'papers'), file);
      return relative && !relative.startsWith('..') ? relative.split(path.sep)[0] : '';
    } catch {return '';}
  };
  context.subscriptions.push(vscode.workspace.registerTextDocumentContentProvider('paper-history', {
    provideTextDocumentContent: uri => virtual.get(uri.toString()) || ''
  }));
  async function show() {
    const preferred = selectedPaper();
    if (panel) {panel.reveal(); return;}
    try {findRoot();} catch(e) {vscode.window.showErrorMessage(e.message); return;}
    panel = vscode.window.createWebviewPanel('paperHistory.panel', '论文历史', vscode.ViewColumn.Active,
      {enableScripts: true, retainContextWhenHidden: true, localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')]});
    const target = panel;
    const webview = target.webview;
    let disposed = false;
    const post = value => disposed ? Promise.resolve(false) : webview.postMessage(value);
    target.iconPath = vscode.Uri.joinPath(context.extensionUri, 'media', 'history.svg');
    const nonce = crypto.randomBytes(24).toString('hex');
    let html = fs.readFileSync(path.join(context.extensionPath, 'media', 'index.html'), 'utf8');
    html = html.replaceAll('{{CSP}}', target.webview.cspSource).replaceAll('{{NONCE}}', nonce)
      .replaceAll('{{SCRIPT}}', target.webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, 'media', 'app.js')).toString())
      .replaceAll('{{STYLE}}', target.webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, 'media', 'style.css')).toString());
    target.webview.html = html;
    target.onDidDispose(() => {disposed = true; if (panel === target) panel = undefined;});
    target.webview.onDidReceiveMessage(async message => {
      const id = message?.id;
      if (!Number.isSafeInteger(id) || typeof message.action !== 'string') return;
      if (disposed) return;
      const reply = data => post({id, data});
      const write = ['snapshot','rename','restore'].includes(message.action);
      let ownsMutation = false;
      try {
        if (write) {
          if (mutation) throw new Error('另一个保存或恢复操作尚未完成。');
          mutation = true; ownsMutation = true;
        }
        if (message.action === 'init') {
          await reply({projects: await api({action:'projects'}), preferred});
        } else if (['history','details','content','projects'].includes(message.action)) {
          await reply(await api(message));
        } else if (message.action === 'snapshot' || message.action === 'rename') {
          const label = await vscode.window.showInputBox({title: message.action === 'snapshot' ? '保存当前论文为命名版本' : '给所选历史版本命名',
            prompt: '例如：投稿前、导师修改后、实验补充完成', value: message.label || '',
            validateInput: value => !value.trim() ? '请输入名称' : value.length > 200 ? '名称不能超过 200 字' : undefined});
          if (label === undefined) {await reply({cancelled:true}); return;}
          if (message.action === 'snapshot') {
            // Validate project before saving any editor buffers.
            await api({action:'history', project:message.project});
            await savePaper(message.project);
          }
          await reply(await api({...message, label}));
          vscode.window.showInformationMessage(message.action === 'snapshot' ? '已保存命名版本：' + label : '版本已命名：' + label);
        } else if (message.action === 'restore') {
          await api({action:'details',project:message.project,sha:message.sha});
          const answer = await vscode.window.showWarningMessage('恢复整篇论文到所选版本？', {
            modal:true, detail: message.project + '\n\n' + (message.title || message.sha.slice(0,10)) +
              '\n\n将先保存编辑器中的修改并创建“恢复前备份”，再恢复该论文的全部已记录文件。恢复后请重新编译 PDF。'
          }, '备份并恢复');
          if (answer !== '备份并恢复') {await reply({cancelled:true}); return;}
          await savePaper(message.project);
          await reply(await api(message));
          vscode.window.showInformationMessage('已恢复论文。原内容保留在“恢复前备份”中；请重新编译 PDF。');
        } else if (message.action === 'diff') {
          const content = await api({...message, action:'content'});
          if (content.binary) throw new Error(content.reason);
          const token = crypto.randomBytes(8).toString('hex');
          const uri = side => vscode.Uri.from({scheme:'paper-history', path:'/' + side + '/' + message.file, query:token});
          const old = uri('历史版本'), current = uri('当前已保存');
          virtual.set(old.toString(),content.before); virtual.set(current.toString(),content.after);
          await vscode.commands.executeCommand('vscode.diff', old, current, path.basename(message.file) + ' · 历史版本 ↔ 当前已保存', {preview:true});
          await reply({opened:true});
        } else throw new Error('未知操作。');
      } catch(e) {await post({id,error:e.message});}
      finally {if (ownsMutation) mutation = false;}
    }, undefined, context.subscriptions);
  }
  context.subscriptions.push(vscode.commands.registerCommand('paperHistory.open', show));
  const provider = {
    getTreeItem: item => item,
    getChildren: () => {
      const item = new vscode.TreeItem('打开论文历史面板');
      item.description = '查看 · 对比 · 恢复'; item.iconPath = new vscode.ThemeIcon('history');
      item.command = {command:'paperHistory.open', title:'打开论文历史'};
      return [item];
    }
  };
  context.subscriptions.push(vscode.window.registerTreeDataProvider('paperHistory.launcher',provider));
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 5);
  status.text = '$(history) 论文历史'; status.tooltip = '查看历史内容、对比修改、恢复版本'; status.command = 'paperHistory.open';
  try {findRoot(); status.show();} catch {}
  context.subscriptions.push(status);
  if (!context.globalState.get('introduced')) {
    try {
      findRoot();
      context.globalState.update('introduced', true);
      vscode.window.showInformationMessage('论文历史面板已就绪：点击底部“论文历史”，即可按时间查看和恢复版本。', '打开面板')
        .then(choice => {if (choice) show();});
    } catch {}
  }
}
exports.activate = activate;
