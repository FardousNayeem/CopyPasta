/// The page a browser gets when it opens `http://<phone-ip>:43210`.
///
/// It is deliberately one self-contained file with no external fonts, scripts
/// or stylesheets: the device serving it is on a LAN that may have no route to
/// the internet at all, so anything fetched from a CDN would simply never
/// arrive.
String buildWebUi({required String deviceName}) {
  return _template.replaceAll('__DEVICE_NAME__', _escape(deviceName));
}

String _escape(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

const _template = r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>CopyPasta on __DEVICE_NAME__</title>
<style>
  :root {
    --bg: #f6f7f9;
    --surface: #ffffff;
    --surface-2: #eef1f5;
    --border: #d8dee6;
    --text: #16191d;
    --text-dim: #5c646e;
    --accent: #0b6fa4;
    --accent-soft: #dceaf4;
    --accent-ink: #ffffff;
    --danger: #a12a12;
    --radius: 12px;
    --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
    --sans: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #131618;
      --surface: #1b1f22;
      --surface-2: #23282c;
      --border: #333a40;
      --text: #e6e8ea;
      --text-dim: #98a1aa;
      --accent: #8dcdff;
      --accent-soft: #1e3646;
      --accent-ink: #002233;
      --danger: #ff9d80;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: var(--sans);
    font-size: 16px;
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
  }
  .wrap { max-width: 860px; margin: 0 auto; padding: 24px 16px 96px; }

  header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
    padding-bottom: 20px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 24px;
  }
  h1 { font-size: 24px; letter-spacing: -0.02em; margin: 0; font-weight: 650; }
  .host { color: var(--text-dim); font-size: 14px; font-family: var(--mono); }

  button {
    font: inherit;
    font-size: 14px;
    border-radius: var(--radius);
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--text);
    padding: 8px 14px;
    cursor: pointer;
    transition: transform .08s ease, background .15s ease, border-color .15s ease;
    white-space: nowrap;
  }
  button:hover { border-color: var(--accent); }
  button:active { transform: translateY(1px); }
  button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  button.primary {
    background: var(--accent);
    color: var(--accent-ink);
    border-color: var(--accent);
    font-weight: 600;
  }
  button.quiet { background: transparent; border-color: transparent; color: var(--text-dim); }
  button.quiet:hover { color: var(--danger); border-color: var(--border); }
  button[disabled] { opacity: .5; cursor: not-allowed; }

  input, textarea {
    font: inherit;
    width: 100%;
    padding: 10px 12px;
    border-radius: var(--radius);
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--text);
  }
  input::placeholder, textarea::placeholder { color: var(--text-dim); }
  input:focus, textarea:focus { outline: 2px solid var(--accent); outline-offset: 1px; border-color: var(--accent); }
  textarea { resize: vertical; min-height: 96px; font-family: var(--mono); font-size: 14px; }
  label { display: block; font-size: 13px; color: var(--text-dim); margin-bottom: 6px; }

  .gate { max-width: 340px; margin: 12vh auto 0; text-align: center; }
  .gate p { color: var(--text-dim); font-size: 14px; }
  .gate input { text-align: center; font-family: var(--mono); font-size: 28px; letter-spacing: .35em; padding-left: .35em; }
  .gate .row { margin-top: 14px; }

  .composer { display: grid; gap: 12px; margin-bottom: 28px; }
  .composer .row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
  .kinds { display: inline-flex; border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; }
  .kinds button { border: 0; border-radius: 0; background: transparent; }
  .kinds button[aria-pressed="true"] { background: var(--accent); color: var(--accent-ink); font-weight: 600; }

  /* Files */
  .dropzone {
    border: 1px dashed var(--border);
    border-radius: var(--radius);
    padding: 14px;
    text-align: center;
    color: var(--text-dim);
    font-size: 14px;
    transition: border-color .15s ease, background .15s ease;
  }
  .dropzone.over { border-color: var(--accent); background: var(--accent-soft); color: var(--text); }
  .dropzone button { margin-right: 8px; }

  ul.files { list-style: none; padding: 0; margin: 0; display: grid; gap: 6px; }
  li.file {
    display: flex;
    align-items: center;
    gap: 10px;
    background: var(--surface-2);
    border-radius: var(--radius);
    padding: 8px 8px 8px 10px;
  }
  .file-badge {
    flex: 0 0 auto;
    width: 40px; height: 40px;
    border-radius: 9px;
    background: var(--accent-soft);
    color: var(--accent);
    display: flex; align-items: center; justify-content: center;
    font-family: var(--mono);
    font-size: 10px;
    font-weight: 700;
    letter-spacing: .02em;
    overflow: hidden;
  }
  .file-badge img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .file-main { min-width: 0; flex: 1 1 auto; }
  .file-name {
    display: block;
    font-size: 14.5px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: var(--text);
    text-decoration: none;
  }
  a.file-name:hover { color: var(--accent); text-decoration: underline; }
  .file-meta { font-family: var(--mono); font-size: 11.5px; color: var(--text-dim); }
  .bar { height: 3px; border-radius: 2px; background: var(--border); overflow: hidden; margin-top: 5px; }
  .bar > span { display: block; height: 100%; background: var(--accent); width: 0; transition: width .15s linear; }

  ul.items { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
  li.item {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 14px 16px;
    display: grid;
    gap: 6px;
  }
  .item-head { display: flex; gap: 12px; align-items: flex-start; justify-content: space-between; }
  .item-title { font-weight: 600; font-size: 17px; word-break: break-word; margin: 0; }
  .item-title a { color: var(--accent); }
  .item-body {
    margin: 0;
    font-family: var(--mono);
    font-size: 13.5px;
    color: var(--text-dim);
    white-space: pre-wrap;
    word-break: break-word;
    max-height: 8.5em;
    overflow: hidden;
  }
  .item-body.open { max-height: none; }
  .item-meta { font-size: 12px; color: var(--text-dim); font-family: var(--mono); }
  .actions { display: flex; gap: 6px; flex-shrink: 0; }

  .state { text-align: center; color: var(--text-dim); padding: 48px 16px; }
  .state strong { display: block; color: var(--text); font-size: 17px; margin-bottom: 6px; }
  .skeleton { background: var(--surface-2); border-radius: var(--radius); height: 84px; animation: pulse 1.2s ease-in-out infinite; }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: .55; } }
  @media (prefers-reduced-motion: reduce) {
    .skeleton { animation: none; }
    button, .bar > span, .dropzone { transition: none; }
  }

  .banner {
    border-radius: var(--radius);
    padding: 10px 14px;
    font-size: 14px;
    margin-bottom: 16px;
    border: 1px solid var(--border);
    background: var(--surface-2);
  }
  .banner.error { border-color: var(--danger); color: var(--danger); }
  .hidden { display: none !important; }

  .toast {
    position: fixed;
    left: 50%;
    bottom: 24px;
    transform: translateX(-50%);
    background: var(--text);
    color: var(--bg);
    padding: 10px 18px;
    border-radius: 999px;
    font-size: 14px;
    font-weight: 500;
    opacity: 0;
    pointer-events: none;
    transition: opacity .2s ease;
  }
  .toast.show { opacity: 1; }
</style>
</head>
<body>
<div class="wrap">

  <section id="gate" class="gate hidden">
    <h1>CopyPasta</h1>
    <p>Enter the PIN shown on <strong>__DEVICE_NAME__</strong>.</p>
    <form id="gate-form">
      <input id="pin" inputmode="numeric" autocomplete="off" maxlength="6"
             pattern="[0-9]*" placeholder="000000" aria-label="PIN">
      <div class="row"><button class="primary" type="submit" style="width:100%">Unlock</button></div>
      <div id="gate-error" class="banner error hidden" style="margin-top:14px"></div>
    </form>
  </section>

  <main id="app" class="hidden">
    <header>
      <h1>CopyPasta</h1>
      <span class="host">__DEVICE_NAME__</span>
    </header>

    <div id="banner" class="banner error hidden"></div>

    <form class="composer" id="composer">
      <div>
        <label for="title">Title</label>
        <input id="title" placeholder="What is this?" autocomplete="off">
      </div>
      <div id="body-wrap">
        <label for="body">Text</label>
        <textarea id="body" placeholder="Paste anything here"></textarea>
      </div>

      <div id="files-wrap">
        <label>Files</label>
        <div class="dropzone" id="dropzone">
          <button type="button" id="browse">Choose files</button>
          <span id="drop-hint">or drop them here</span>
          <input type="file" id="file-input" multiple class="hidden">
        </div>
        <ul class="files" id="pending" style="margin-top:8px"></ul>
      </div>

      <div class="row">
        <div class="kinds" role="group" aria-label="Item kind">
          <button type="button" id="kind-note" aria-pressed="true">Note</button>
          <button type="button" id="kind-link" aria-pressed="false">Link</button>
        </div>
        <button class="primary" type="submit" id="save">Save</button>
        <button type="button" id="refresh">Refresh</button>
      </div>
    </form>

    <ul class="items" id="items"></ul>
    <div id="list-state" class="state hidden"></div>
  </main>

</div>
<div class="toast" id="toast" role="status" aria-live="polite"></div>

<script>
(function () {
  "use strict";

  var kind = "note";
  var items = [];
  var pending = [];
  var pollTimer = null;

  var $ = function (id) { return document.getElementById(id); };

  function toast(message) {
    var el = $("toast");
    el.textContent = message;
    el.classList.add("show");
    clearTimeout(el._t);
    el._t = setTimeout(function () { el.classList.remove("show"); }, 1800);
  }

  function api(path, options) {
    options = options || {};
    options.credentials = "same-origin";
    options.headers = Object.assign(
      { "content-type": "application/json" },
      options.headers || {}
    );
    return fetch(path, options);
  }

  function readableSize(bytes) {
    if (!bytes && bytes !== 0) return "";
    if (bytes < 1024) return bytes + " B";
    var units = ["KB", "MB", "GB", "TB"];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return value.toFixed(value >= 100 ? 0 : 1) + " " + units[unit];
  }

  function extensionOf(name) {
    var dot = name.lastIndexOf(".");
    if (dot <= 0 || dot === name.length - 1) return "FILE";
    return name.slice(dot + 1, dot + 5).toUpperCase();
  }

  // ---- auth gate ---------------------------------------------------------

  function showGate(message) {
    $("app").classList.add("hidden");
    $("gate").classList.remove("hidden");
    if (message) {
      $("gate-error").textContent = message;
      $("gate-error").classList.remove("hidden");
    }
    $("pin").focus();
  }

  function showApp() {
    $("gate").classList.add("hidden");
    $("app").classList.remove("hidden");
  }

  $("gate-form").addEventListener("submit", function (event) {
    event.preventDefault();
    var pin = $("pin").value.trim();
    $("gate-error").classList.add("hidden");
    api("/api/auth", { method: "POST", body: JSON.stringify({ pin: pin }) })
      .then(function (response) {
        if (response.ok) {
          showApp();
          load();
          startPolling();
          return;
        }
        return response.json().catch(function () { return {}; }).then(function (body) {
          $("gate-error").textContent = body.error || "That PIN did not work.";
          $("gate-error").classList.remove("hidden");
        });
      })
      .catch(function () {
        $("gate-error").textContent = "Could not reach the device.";
        $("gate-error").classList.remove("hidden");
      });
  });

  // ---- file staging ------------------------------------------------------

  function addFiles(fileList) {
    for (var i = 0; i < fileList.length; i++) {
      pending.push({ file: fileList[i], progress: 0, uploading: false });
    }
    if (!$("title").value.trim() && pending.length) {
      $("title").value = pending[0].file.name;
    }
    renderPending();
  }

  function renderPending() {
    var list = $("pending");
    list.innerHTML = "";
    pending.forEach(function (entry, index) {
      var li = document.createElement("li");
      li.className = "file";

      var badge = document.createElement("div");
      badge.className = "file-badge";
      badge.textContent = extensionOf(entry.file.name);
      li.appendChild(badge);

      var main = document.createElement("div");
      main.className = "file-main";

      var name = document.createElement("span");
      name.className = "file-name";
      name.textContent = entry.file.name;
      main.appendChild(name);

      var meta = document.createElement("span");
      meta.className = "file-meta";
      meta.textContent = readableSize(entry.file.size);
      main.appendChild(meta);

      if (entry.uploading) {
        var bar = document.createElement("div");
        bar.className = "bar";
        var fill = document.createElement("span");
        fill.style.width = Math.round(entry.progress * 100) + "%";
        bar.appendChild(fill);
        main.appendChild(bar);
      }

      li.appendChild(main);

      if (!entry.uploading) {
        var remove = document.createElement("button");
        remove.type = "button";
        remove.className = "quiet";
        remove.textContent = "Remove";
        remove.setAttribute("aria-label", "Remove " + entry.file.name);
        remove.addEventListener("click", function () {
          pending.splice(index, 1);
          renderPending();
        });
        li.appendChild(remove);
      }

      list.appendChild(li);
    });
  }

  $("browse").addEventListener("click", function () { $("file-input").click(); });
  $("file-input").addEventListener("change", function (event) {
    addFiles(event.target.files);
    event.target.value = "";
  });

  // Dropping a file anywhere else on the page would otherwise make the browser
  // navigate away from the app and open the file itself.
  ["dragenter", "dragover", "dragleave", "drop"].forEach(function (name) {
    document.addEventListener(name, function (event) { event.preventDefault(); });
  });
  var zone = $("dropzone");
  zone.addEventListener("dragover", function () { zone.classList.add("over"); });
  zone.addEventListener("dragleave", function () { zone.classList.remove("over"); });
  zone.addEventListener("drop", function (event) {
    zone.classList.remove("over");
    if (event.dataTransfer && event.dataTransfer.files.length) {
      addFiles(event.dataTransfer.files);
    }
  });

  // XMLHttpRequest rather than fetch, because fetch reports no upload
  // progress and these can be large files over Wi-Fi.
  function uploadOne(entry) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", "/api/upload");
      xhr.withCredentials = true;
      xhr.setRequestHeader("content-type", "application/octet-stream");
      // Header values must be latin-1, and file names are not.
      xhr.setRequestHeader("x-file-name", encodeURIComponent(entry.file.name));

      xhr.upload.onprogress = function (event) {
        if (!event.lengthComputable) return;
        entry.progress = event.loaded / event.total;
        renderPending();
      };
      xhr.onload = function () {
        var body = {};
        try { body = JSON.parse(xhr.responseText); } catch (error) { void error; }
        if (xhr.status === 200 && body.attachment) {
          resolve(body.attachment);
        } else {
          reject(new Error(body.error || ("upload failed (" + xhr.status + ")")));
        }
      };
      xhr.onerror = function () { reject(new Error("the connection dropped")); };
      xhr.send(entry.file);
    });
  }

  function uploadAll() {
    if (!pending.length) return Promise.resolve([]);
    var uploaded = [];
    return pending.reduce(function (chain, entry) {
      return chain.then(function () {
        entry.uploading = true;
        entry.progress = 0;
        renderPending();
        return uploadOne(entry).then(function (attachment) {
          uploaded.push(attachment);
        });
      });
    }, Promise.resolve()).then(function () { return uploaded; });
  }

  // ---- list --------------------------------------------------------------

  function setListState(html) {
    var state = $("list-state");
    if (!html) {
      state.classList.add("hidden");
      state.innerHTML = "";
      return;
    }
    state.classList.remove("hidden");
    state.innerHTML = html;
  }

  function load(silent) {
    if (!silent) {
      $("items").innerHTML =
        '<li class="skeleton"></li><li class="skeleton"></li><li class="skeleton"></li>';
      setListState("");
    }
    return api("/api/items")
      .then(function (response) {
        if (response.status === 401) { showGate("Session expired. Enter the PIN again."); return null; }
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.json();
      })
      .then(function (body) {
        if (!body) return;
        items = (body.items || []).filter(function (item) { return !item.deleted; });
        items.sort(function (a, b) { return (b.createdAt || "").localeCompare(a.createdAt || ""); });
        render();
        $("banner").classList.add("hidden");
      })
      .catch(function (error) {
        $("items").innerHTML = "";
        setListState(
          "<strong>Lost the connection</strong>" +
          "Check that CopyPasta is still running on __DEVICE_NAME__ and that this " +
          "machine is on the same Wi-Fi."
        );
        void error;
      });
  }

  function formatDate(iso) {
    var date = new Date(iso);
    if (isNaN(date.getTime())) return "";
    return date.toLocaleString();
  }

  function attachmentList(attachments) {
    var list = document.createElement("ul");
    list.className = "files";

    attachments.forEach(function (attachment) {
      var li = document.createElement("li");
      li.className = "file";

      var badge = document.createElement("div");
      badge.className = "file-badge";
      if (attachment.mimeType && attachment.mimeType.indexOf("image/") === 0) {
        // A real thumbnail of the real file, served inline by the device.
        var img = document.createElement("img");
        img.src = "/api/files/" + encodeURIComponent(attachment.id) + "?inline=1";
        img.alt = attachment.name;
        img.loading = "lazy";
        badge.appendChild(img);
      } else {
        badge.textContent = extensionOf(attachment.name || "");
      }
      li.appendChild(badge);

      var main = document.createElement("div");
      main.className = "file-main";

      var link = document.createElement("a");
      link.className = "file-name";
      link.href = "/api/files/" + encodeURIComponent(attachment.id);
      link.textContent = attachment.name;
      link.setAttribute("download", attachment.name);
      main.appendChild(link);

      var meta = document.createElement("span");
      meta.className = "file-meta";
      meta.textContent = readableSize(attachment.size);
      main.appendChild(meta);

      li.appendChild(main);
      list.appendChild(li);
    });

    return list;
  }

  function render() {
    var list = $("items");
    list.innerHTML = "";

    if (items.length === 0) {
      setListState(
        "<strong>Nothing saved yet</strong>Add a note above, or save one on the phone and refresh."
      );
      return;
    }
    setListState("");

    items.forEach(function (item) {
      var li = document.createElement("li");
      li.className = "item";

      var head = document.createElement("div");
      head.className = "item-head";

      var title = document.createElement("p");
      title.className = "item-title";
      if (item.kind === "link") {
        var anchor = document.createElement("a");
        anchor.href = /^https?:\/\//i.test(item.title) ? item.title : "https://" + item.title;
        anchor.target = "_blank";
        anchor.rel = "noopener noreferrer";
        anchor.textContent = item.title;
        title.appendChild(anchor);
      } else {
        title.textContent = item.title || "Untitled";
      }
      head.appendChild(title);

      var actions = document.createElement("div");
      actions.className = "actions";

      var copyButton = document.createElement("button");
      copyButton.textContent = "Copy";
      copyButton.addEventListener("click", function () {
        copyText(item.body && item.body.trim() ? item.body : item.title);
      });
      actions.appendChild(copyButton);

      var deleteButton = document.createElement("button");
      deleteButton.className = "quiet";
      deleteButton.textContent = "Delete";
      deleteButton.setAttribute("aria-label", "Delete " + (item.title || "item"));
      deleteButton.addEventListener("click", function () { remove(item); });
      actions.appendChild(deleteButton);

      head.appendChild(actions);
      li.appendChild(head);

      if (item.body && item.body.trim()) {
        var body = document.createElement("p");
        body.className = "item-body";
        body.textContent = item.body;
        body.addEventListener("click", function () { body.classList.toggle("open"); });
        li.appendChild(body);
      }

      var attachments = item.attachments || [];
      if (attachments.length) li.appendChild(attachmentList(attachments));

      var meta = document.createElement("p");
      meta.className = "item-meta";
      var label = item.kind === "link" ? "Link" : "Note";
      if (attachments.length) {
        label += " · " + attachments.length + " file" + (attachments.length === 1 ? "" : "s");
      }
      meta.textContent = label + " · " + formatDate(item.createdAt);
      li.appendChild(meta);

      list.appendChild(li);
    });
  }

  // ---- clipboard ---------------------------------------------------------

  // navigator.clipboard is only exposed in a secure context. This page is
  // served over plain HTTP on the LAN, so on most browsers the modern API is
  // simply absent and the textarea fallback is the one that actually runs.
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(
        function () { toast("Copied"); },
        function () { legacyCopy(text); }
      );
      return;
    }
    legacyCopy(text);
  }

  function legacyCopy(text) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.top = "-1000px";
    document.body.appendChild(area);
    area.select();
    area.setSelectionRange(0, area.value.length);
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (error) { ok = false; }
    document.body.removeChild(area);
    toast(ok ? "Copied" : "Press Ctrl+C to copy");
  }

  // ---- write -------------------------------------------------------------

  function setKind(next) {
    kind = next;
    $("kind-note").setAttribute("aria-pressed", String(next === "note"));
    $("kind-link").setAttribute("aria-pressed", String(next === "link"));
    $("body-wrap").classList.toggle("hidden", next === "link");
    $("files-wrap").classList.toggle("hidden", next === "link");
    $("title").placeholder = next === "link" ? "https://" : "What is this?";
  }
  $("kind-note").addEventListener("click", function () { setKind("note"); });
  $("kind-link").addEventListener("click", function () { setKind("link"); });

  $("composer").addEventListener("submit", function (event) {
    event.preventDefault();
    var title = $("title").value.trim();
    var body = kind === "link" ? "" : $("body").value;
    var hasFiles = kind === "note" && pending.length > 0;

    if (!title && !body.trim() && !hasFiles) { toast("Nothing to save"); return; }

    $("save").disabled = true;
    $("save").textContent = hasFiles ? "Uploading" : "Saving";

    (hasFiles ? uploadAll() : Promise.resolve([]))
      .then(function (attachments) {
        $("save").textContent = "Saving";
        return api("/api/items", {
          method: "POST",
          body: JSON.stringify({
            kind: kind,
            title: title,
            body: body,
            attachments: attachments
          })
        });
      })
      .then(function (response) {
        if (response.status === 401) { showGate("Session expired. Enter the PIN again."); return; }
        if (!response.ok) throw new Error("HTTP " + response.status);
        $("title").value = "";
        $("body").value = "";
        pending = [];
        renderPending();
        toast("Saved");
        return load(true);
      })
      .catch(function (error) {
        showBanner("Could not save: " + (error && error.message ? error.message : "unknown error"));
        // Anything already uploaded is unreferenced and the device clears it
        // on its own, so the only thing to reset here is the progress bars.
        pending.forEach(function (entry) { entry.uploading = false; entry.progress = 0; });
        renderPending();
      })
      .then(function () {
        $("save").disabled = false;
        $("save").textContent = "Save";
      });
  });

  function remove(item) {
    if (!window.confirm("Delete \"" + (item.title || "this item") + "\"?")) return;
    api("/api/items/" + encodeURIComponent(item.id), { method: "DELETE" })
      .then(function (response) {
        if (response.status === 401) { showGate("Session expired. Enter the PIN again."); return; }
        return load(true);
      })
      .catch(function () { showBanner("Could not delete. Try again."); });
  }

  function showBanner(message) {
    $("banner").textContent = message;
    $("banner").classList.remove("hidden");
  }

  $("refresh").addEventListener("click", function () { load(); });

  // ---- lifecycle ---------------------------------------------------------

  function startPolling() {
    if (pollTimer) return;
    pollTimer = setInterval(function () {
      // Polling during an upload would redraw the list under the progress bars.
      var busy = pending.some(function (entry) { return entry.uploading; });
      if (document.visibilityState === "visible" && !busy) load(true);
    }, 5000);
  }

  setKind("note");

  // The auth cookie may already be set from an earlier visit, so try the real
  // endpoint first and only fall back to the gate on a 401.
  api("/api/items").then(function (response) {
    if (response.ok) {
      showApp();
      load();
      startPolling();
    } else {
      showGate();
    }
  }).catch(function () { showGate(); });
})();
</script>
</body>
</html>
''';
