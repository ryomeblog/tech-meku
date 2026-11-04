/** 管理用Webページ（A01）。Cloudflare Access で保護された /admin で配信する */
export const ADMIN_HTML = `<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TechMeku 管理</title>
<style>
:root{--bg:#fff;--ink:#111827;--sub:#6b7280;--line:#e5e7eb;--accent:#0891b2;--warn:#c2410c}
@media (prefers-color-scheme:dark){:root{--bg:#0b0f14;--ink:#e5e7eb;--sub:#9ca3af;--line:#1f2937;--accent:#06b6d4;--warn:#fb923c}}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.6 system-ui,sans-serif}
main{max-width:960px;margin:0 auto;padding:16px}
h1{font-size:20px}h2{font-size:16px;margin-top:28px;border-bottom:1px solid var(--line);padding-bottom:4px}
.row{border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin:8px 0}
.meta{color:var(--sub);font-size:12px}.hidden{color:var(--warn);font-weight:600}
button{font:inherit;border:1px solid var(--line);background:none;color:var(--ink);border-radius:6px;padding:3px 10px;margin:4px 4px 0 0;cursor:pointer}
button.danger{border-color:var(--warn);color:var(--warn)}
input{font:inherit;padding:4px 8px;border:1px solid var(--line);border-radius:6px;background:none;color:var(--ink)}
pre{white-space:pre-wrap;margin:6px 0;font:inherit}
</style></head><body><main>
<h1>TechMeku 管理</h1>
<input id="q" placeholder="絞り込み（タイトル・本文・ニックネーム）"> <button onclick="load()">再読み込み</button>
<h2>投稿</h2><div id="posts"></div>
<h2>コメント</h2><div id="comments"></div>
<h2>停止中のアカウント</h2><div id="bans"></div>
</main><script>
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const t=ms=>ms?new Date(ms).toLocaleString('ja-JP'):'';
let data={posts:[],comments:[],bans:[]};
async function api(path,body){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body||{})});if(!r.ok)console.error(await r.text());await load();}
function userBtns(x){return x.user_id?(x.banned?'<span class="hidden">停止中</span>':'<button class="danger" data-ban="'+esc(x.user_id)+'">アカウント停止</button>'):'';}
function render(){
 const q=document.getElementById('q').value.trim();
 const m=x=>!q||[x.title,x.body,x.nickname].join(' ').includes(q);
 document.getElementById('posts').innerHTML=data.posts.filter(m).map(p=>'<div class="row"><b>'+esc(p.title)+'</b> '+(p.status!=='active'?'<span class="hidden">非表示</span>':'')+
  '<div class="meta">'+esc(p.nickname)+' ・ 通報 '+p.report_count+'（'+esc(p.reasons)+'） ・ 期限 '+t(p.expires_at)+'</div><pre>'+esc(p.body)+'</pre>'+
  '<button data-a="posts/'+p.id+'/hide">非表示</button><button data-a="posts/'+p.id+'/restore">復帰</button><button class="danger" data-a="posts/'+p.id+'/delete">削除</button>'+userBtns(p)+'</div>').join('')||'<p class="meta">なし</p>';
 document.getElementById('comments').innerHTML=data.comments.filter(m).map(c=>'<div class="row">'+(c.status!=='active'?'<span class="hidden">非表示</span>':'')+
  '<div class="meta">'+esc(c.nickname)+' ・ 通報 '+c.report_count+'（'+esc(c.reasons)+'） ・ '+t(c.created_at)+'</div><pre>'+esc(c.body)+'</pre>'+
  '<button data-a="comments/'+c.id+'/hide">非表示</button><button data-a="comments/'+c.id+'/restore">復帰</button><button class="danger" data-a="comments/'+c.id+'/delete">削除</button>'+userBtns(c)+'</div>').join('')||'<p class="meta">なし</p>';
 document.getElementById('bans').innerHTML=data.bans.map(b=>'<div class="row"><div class="meta">'+esc(b.sub_hash.slice(0,12))+'… ・ '+t(b.created_at)+' ・ '+esc(b.reason)+'</div><button data-unban="'+esc(b.sub_hash)+'">停止を解除</button></div>').join('')||'<p class="meta">なし</p>';
}
async function load(){const r=await fetch('/admin/api/reports');data=await r.json();render();}
document.addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
 if(b.dataset.a){if(b.dataset.a.endsWith('/delete')&&!confirm('削除しますか？'))return;api('/admin/api/'+b.dataset.a);}
 else if(b.dataset.ban){const reason=prompt('停止理由');if(reason===null)return;api('/admin/api/users/'+b.dataset.ban+'/ban',{reason});}
 else if(b.dataset.unban){api('/admin/api/bans/'+b.dataset.unban+'/unban');}});
document.getElementById('q').addEventListener('input',render);
load();
</script></body></html>`;
