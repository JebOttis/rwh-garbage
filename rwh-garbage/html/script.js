const root = document.querySelector('body');
const frame = document.querySelector('.terminal-frame');
const opNameEl = document.getElementById('op-name');
const plateEl = document.getElementById('truck-plate');
const bagCountEl = document.getElementById('bag-count');
const systemLogEl = document.getElementById('system-log');
const summaryLogEl = document.getElementById('summary-log');
const exitBtn = document.getElementById('btn-exit');

let visible = false;

function appendLog(el, text) {
    if (!el) return;
    const p = document.createElement('p');
    p.textContent = `> ${text}`;
    el.appendChild(p);
    el.scrollTop = el.scrollHeight;
}

function setVisible(state) {
    visible = state;
    root.style.display = state ? 'block' : 'none';
}

// Initially hidden
setVisible(false);

// Listen for messages from client.lua
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    if (data.action === 'open') {
        opNameEl.textContent = data.operator || 'UNKNOWN';
        plateEl.textContent = data.truckPlate || 'N/A';
        bagCountEl.textContent = data.bagCount != null ? data.bagCount : 0;
        if (data.logLine) appendLog(systemLogEl, data.logLine);
        setVisible(true);
    }

    if (data.action === 'close') {
        setVisible(false);
    }

    if (data.action === 'summary') {
        summaryLogEl.innerHTML = '';
        (data.lines || ['NO DATA']).forEach((line) => appendLog(summaryLogEl, line));
    }

    if (data.action === 'updateBags') {
        bagCountEl.textContent = data.bagCount != null ? data.bagCount : 0;
    }
});

function nuiPost(name, payload = {}) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(payload),
    }).catch(() => {});
}

// Button handlers
Array.from(document.querySelectorAll('[data-action]')).forEach((btn) => {
    btn.addEventListener('click', () => {
        const action = btn.dataset.action;
        if (!action) return;

        if (action === 'rentTruck') {
            const hoursEl = document.getElementById('rent-hours');
            const hours = hoursEl ? parseInt(hoursEl.value, 10) || 1 : 1;
            appendLog(systemLogEl, `Command queued: rentTruck (${hours}h)`);
            nuiPost('rentTruck', { hours });
            return;
        }

        appendLog(systemLogEl, `Command queued: ${action}`);
        nuiPost(action, {});
    });
});

exitBtn.addEventListener('click', () => {
    nuiPost('close', {});
});
