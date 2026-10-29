import { AgentError } from './chatgpt-auth.mjs';

// Read only the history namespace. Do not merge connection, auth or key data.
export function historyExport(history, now = new Date()) {
  if (!Number.isSafeInteger(history?.revision) || history.revision < 0 ||
      !Array.isArray(history.events) || history.events.length > 20_000 ||
      history.events.some(event => !event || typeof event.event_id !== 'string' ||
        !event.event_id || ['d4', 'D4'].includes(event.sensitivity))) {
    throw new AgentError('invalid_history', 500);
  }
  return {
    format: 'personal-os.web-history.v1',
    exported_at: now.toISOString(),
    source_revision: history.revision,
    events: structuredClone(history.events),
  };
}

// This page contains no embedded personal data and makes no automatic request.
export const historyExportPage = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>导出 Personal OS 历史</title>
<style>body{font:17px system-ui;max-width:560px;margin:8vh auto;padding:24px;background:#f3f7f3;color:#123c32;line-height:1.6}button{font:inherit;padding:14px 20px;border-radius:12px;background:#123c32;color:white;border:0}a{color:#315c4c}button:disabled{opacity:.6}</style>
<h1>导出个人历史</h1><p>包含已保存的资料、目标、计划、执行、反馈和复盘事件，保留原始版本与引用。</p>
<p>网关不会打包 AI 连接配置、API 密钥、CLI 登录文件或安装密钥。你自己写入资料中的内容会原样导出。</p>
<p>文件是明文，请保存在自己的设备上。可在空白网关选择此文件，校验并确认后恢复个人历史；不能替代包含登录凭据的服务器私有备份。</p>
<button id="download">下载历史 JSON</button><p id="message" role="status"></p><a href="/">返回应用</a> · <a href="/?restore=history">恢复历史（仅空白网关）</a>
<script>
const button=document.querySelector('#download'),message=document.querySelector('#message');
button.onclick=async()=>{
  button.disabled=true;message.textContent='正在准备历史文件…';
  try{
    const response=await fetch('/api/history/export',{headers:{'X-Personal-OS':'1'},redirect:'error',cache:'no-store'});
    if(!response.ok)throw Error();
    const value=await response.json();
    if(value.format!=='personal-os.web-history.v1'||!Array.isArray(value.events))throw Error();
    const blob=new Blob([JSON.stringify(value,null,2)+'\\n'],{type:'application/json;charset=utf-8'});
    const url=URL.createObjectURL(blob),link=document.createElement('a');
    link.href=url;link.download='personal-os-history-'+new Date().toISOString().slice(0,10)+'.json';
    document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
    message.textContent='已交给浏览器下载，请检查下载文件。导出没有修改历史或调用 AI。';
  }catch{message.textContent='导出失败，历史未修改。请检查网关后重试。';}
  finally{button.disabled=false;}
};
</script></html>`;
