// Osprey – Apple Design & Mole-Style Desktop HUD Widget System

(function () {
  'use strict';

  let currentOverview = null;
  let currentPreset = 'm'; // 's', 'm', 'l'
  let pollInterval = 1000;
  let pollTimer = null;
  let activeDriveIndex = 0;

  // Local history buffers for smooth sparklines
  const cpuHistory = [];
  const netDownHistory = [];
  const netUpHistory = [];
  const MAX_HISTORY = 24;

  // DOM Elements
  const hudCard = document.getElementById('hudCard');
  const btnSizeS = document.getElementById('btnSizeS');
  const btnSizeM = document.getElementById('btnSizeM');
  const btnSizeL = document.getElementById('btnSizeL');

  const btnRangeLive = document.getElementById('btnRangeLive');
  const btnRange1h = document.getElementById('btnRange1h');
  const btnRange4h = document.getElementById('btnRange4h');
  const historyDrawer = document.getElementById('historyDrawer');
  const historySlider = document.getElementById('historySlider');
  const historyTimeVal = document.getElementById('historyTimeVal');

  const btnThemeToggle = document.getElementById('btnThemeToggle');
  const iconSun = document.getElementById('iconSun');
  const iconMoon = document.getElementById('iconMoon');

  const btnLock = document.getElementById('btnLock');
  const iconUnlock = document.getElementById('iconUnlock');
  const iconLock = document.getElementById('iconLock');
  let isLocked = false;

  const btnOpenSmart = document.getElementById('btnOpenSmart');
  const smartModal = document.getElementById('smartModal');
  const btnCloseSmart = document.getElementById('btnCloseSmart');
  const diskTitleRow = document.getElementById('diskTitleRow');
  const diskSmartQuickLink = document.getElementById('diskSmartQuickLink');

  const btnExport = document.getElementById('btnExport');
  const reportModal = document.getElementById('reportModal');
  const btnCloseReport = document.getElementById('btnCloseReport');
  const reportText = document.getElementById('reportText');
  const btnCopyReport = document.getElementById('btnCopyReport');
  const copyNotice = document.getElementById('copyNotice');

  // Advisory Elements
  const advisoryBadgeBtn = document.getElementById('advisoryBadgeBtn');
  const advisoryBadgeText = document.getElementById('advisoryBadgeText');
  const advisoryModal = document.getElementById('advisoryModal');
  const btnCloseAdvisory = document.getElementById('btnCloseAdvisory');
  const btnSendNotification = document.getElementById('btnSendNotification');
  const btnLaunchActivityMonitor = document.getElementById('btnLaunchActivityMonitor');
  const notifyNotice = document.getElementById('notifyNotice');
  const cpuTitleRow = document.getElementById('cpuTitleRow');
  const memTitleRow = document.getElementById('memTitleRow');

  // Canvases
  const cpuCanvas = document.getElementById('cpuSparkCanvas');
  const netDownCanvas = document.getElementById('netDownCanvas');
  const netUpCanvas = document.getElementById('netUpCanvas');

  // Sections
  const secCpu = document.getElementById('secCpu');
  const secMemory = document.getElementById('secMemory');
  const secDisk = document.getElementById('secDisk');
  const secPower = document.getElementById('secPower');
  const secNetwork = document.getElementById('secNetwork');
  const secProcesses = document.getElementById('secProcesses');

  function init() {
    setupEventListeners();
    applyPreset('m');
    fetchTelemetry();
    pollTimer = setInterval(fetchTelemetry, pollInterval);
  }

  function setupEventListeners() {
    // Size Presets
    btnSizeS.addEventListener('click', () => applyPreset('s'));
    btnSizeM.addEventListener('click', () => applyPreset('m'));
    btnSizeL.addEventListener('click', () => applyPreset('l'));

    // History Presets
    btnRangeLive.addEventListener('click', () => setHistoryRange('live'));
    btnRange1h.addEventListener('click', () => setHistoryRange('1h'));
    btnRange4h.addEventListener('click', () => setHistoryRange('4h'));

    historySlider.addEventListener('input', (e) => {
      const val = parseInt(e.target.value, 10);
      if (val === 100) {
        historyTimeVal.textContent = 'Now';
      } else {
        const minsAgo = Math.round(((100 - val) / 100) * 60);
        historyTimeVal.textContent = `-${minsAgo}m`;
      }
    });

    // Theme Toggle
    btnThemeToggle.addEventListener('click', toggleTheme);

    // Lock Toggle
    btnLock.addEventListener('click', () => {
      isLocked = !isLocked;
      iconUnlock.classList.toggle('hidden', isLocked);
      iconLock.classList.toggle('hidden', !isLocked);
      btnLock.classList.toggle('active', isLocked);
    });

    // Advisory Modal & Notifications
    if (advisoryBadgeBtn) advisoryBadgeBtn.addEventListener('click', openAdvisoryModal);
    if (btnCloseAdvisory) btnCloseAdvisory.addEventListener('click', () => advisoryModal.classList.add('hidden'));

    if (btnSendNotification) {
      btnSendNotification.addEventListener('click', async () => {
        try {
          const res = await fetch('/api/notify');
          if (res.ok) {
            notifyNotice.classList.add('visible');
            setTimeout(() => notifyNotice.classList.remove('visible'), 2500);
          }
        } catch (e) {
          console.error(e);
        }
      });
    }

    if (btnLaunchActivityMonitor) {
      btnLaunchActivityMonitor.addEventListener('click', () => {
        fetch('/api/open/activity-monitor');
      });
    }

    // Clicking section titles opens Activity Monitor (like Mole Widget)
    if (cpuTitleRow) cpuTitleRow.addEventListener('click', () => fetch('/api/open/activity-monitor'));
    if (memTitleRow) memTitleRow.addEventListener('click', () => fetch('/api/open/activity-monitor'));

    // Modals
    btnOpenSmart.addEventListener('click', openSmartModal);
    if (diskTitleRow) diskTitleRow.addEventListener('click', openSmartModal);
    if (diskSmartQuickLink) diskSmartQuickLink.addEventListener('click', openSmartModal);
    btnCloseSmart.addEventListener('click', () => smartModal.classList.add('hidden'));

    btnExport.addEventListener('click', openReportModal);
    btnCloseReport.addEventListener('click', () => reportModal.classList.add('hidden'));

    btnCopyReport.addEventListener('click', () => {
      if (reportText) {
        navigator.clipboard.writeText(reportText.value).then(() => {
          copyNotice.classList.add('visible');
          setTimeout(() => copyNotice.classList.remove('visible'), 2000);
        });
      }
    });

    // Close modals on escape
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        smartModal.classList.add('hidden');
        reportModal.classList.add('hidden');
        if (advisoryModal) advisoryModal.classList.add('hidden');
      }
    });
  }


  function applyPreset(preset) {
    currentPreset = preset;
    [btnSizeS, btnSizeM, btnSizeL].forEach(b => b.classList.remove('active'));
    hudCard.classList.remove('size-s', 'size-m', 'size-l');

    if (preset === 's') {
      btnSizeS.classList.add('active');
      hudCard.classList.add('size-s');
      secCpu.classList.remove('hidden');
      secMemory.classList.remove('hidden');
      secDisk.classList.add('hidden');
      secPower.classList.add('hidden');
      secNetwork.classList.add('hidden');
      secProcesses.classList.add('hidden');
    } else if (preset === 'm') {
      btnSizeM.classList.add('active');
      hudCard.classList.add('size-m');
      secCpu.classList.remove('hidden');
      secMemory.classList.remove('hidden');
      secDisk.classList.remove('hidden');
      secPower.classList.remove('hidden');
      secNetwork.classList.add('hidden');
      secProcesses.classList.add('hidden');
    } else {
      btnSizeL.classList.add('active');
      hudCard.classList.add('size-l');
      secCpu.classList.remove('hidden');
      secMemory.classList.remove('hidden');
      secDisk.classList.remove('hidden');
      secPower.classList.remove('hidden');
      secNetwork.classList.remove('hidden');
      secProcesses.classList.remove('hidden');
    }
  }

  function setHistoryRange(range) {
    [btnRangeLive, btnRange1h, btnRange4h].forEach(b => b.classList.remove('active'));
    if (range === 'live') {
      btnRangeLive.classList.add('active');
      historyDrawer.classList.add('hidden');
    } else if (range === '1h') {
      btnRange1h.classList.add('active');
      historyDrawer.classList.remove('hidden');
    } else {
      btnRange4h.classList.add('active');
      historyDrawer.classList.remove('hidden');
    }
  }

  function toggleTheme() {
    const isDark = document.body.classList.contains('theme-dark');
    if (isDark) {
      document.body.classList.remove('theme-dark');
      document.body.classList.add('theme-light');
      iconSun.classList.add('hidden');
      iconMoon.classList.remove('hidden');
    } else {
      document.body.classList.remove('theme-light');
      document.body.classList.add('theme-dark');
      iconSun.classList.remove('hidden');
      iconMoon.classList.add('hidden');
    }
  }

  async function fetchTelemetry() {
    try {
      const res = await fetch('/api/overview');
      if (!res.ok) return;
      const data = await res.json();
      currentOverview = data;
      renderTelemetry(data);
    } catch (err) {
      console.warn('Telemetry fetch error:', err);
    }
  }

  function renderTelemetry(d) {
    // 1. Header & Health
    const healthDot = document.getElementById('healthDot');
    const healthScoreVal = document.getElementById('healthScoreVal');
    const chipNameVal = document.getElementById('chipNameVal');
    const memSummaryVal = document.getElementById('memSummaryVal');
    const osVal = document.getElementById('osVal');
    const uptimeVal = document.getElementById('uptimeVal');

    if (d.header) {
      healthScoreVal.textContent = d.header.health_score.score;
      healthDot.style.color = d.header.health_score.dot_color;
      chipNameVal.textContent = d.header.chip_name;
      memSummaryVal.textContent = d.header.total_ram_formatted;
      osVal.textContent = d.header.os_name ? `${d.header.os_name} ${d.header.os_version}` : `macOS ${d.header.os_version}`;
      uptimeVal.textContent = `up ${d.header.uptime_formatted}`;
    }

    // Advisory Badge
    if (d.advisory && advisoryBadgeBtn) {
      const adv = d.advisory;
      if (adv.should_reboot || (adv.triggers && adv.triggers.length > 0)) {
        advisoryBadgeBtn.classList.remove('hidden');
        const isUrgent = adv.level === 'Critical' || adv.level === 'Recommended';
        advisoryBadgeBtn.classList.toggle('critical', isUrgent);
        advisoryBadgeText.textContent = `${adv.swap_used_formatted} Swap · ${adv.level}`;
      } else {
        advisoryBadgeBtn.classList.add('hidden');
      }
    }


    // 2. CPU
    if (d.cpu) {
      const totalPct = d.cpu.total_percent || 0;
      document.getElementById('cpuTotalVal').textContent = `${totalPct.toFixed(1)}%`;
      const cpuBar = document.getElementById('cpuTotalBar');
      cpuBar.style.width = `${Math.min(100, totalPct)}%`;
      setBarColor(cpuBar, totalPct / 100);

      document.getElementById('cpuTempBadge').textContent = d.cpu.temp_celsius ? `${Math.round(d.cpu.temp_celsius)}°C` : '--°C';
      document.getElementById('cpuLoadVal').textContent = `${d.cpu.load_average[0].toFixed(2)} / ${d.cpu.load_average[1].toFixed(2)} / ${d.cpu.load_average[2].toFixed(2)}`;

      // Render top cores
      const coresContainer = document.getElementById('cpuCoresContainer');
      if (coresContainer && d.cpu.top_cores) {
        coresContainer.innerHTML = d.cpu.top_cores.map(c => `
          <div class="metric-row">
            <span class="row-label">Core${c.index + 1}</span>
            <div class="bar-track">
              <div class="bar-fill" style="width: ${Math.min(100, c.usage_percent)}%;"></div>
            </div>
            <span class="row-val">${c.usage_percent.toFixed(1)}%</span>
          </div>
        `).join('');
      }

      // Sparkline history
      cpuHistory.push(totalPct);
      if (cpuHistory.length > MAX_HISTORY) cpuHistory.shift();
      drawSparkline(cpuCanvas, cpuHistory, '#a6d189');
    }

    // 3. Memory
    if (d.memory) {
      document.getElementById('memUsedPctBadge').textContent = `${Math.round(d.memory.used_percent)}%`;
      document.getElementById('memUsedVal').textContent = `${d.memory.used_percent.toFixed(1)}%`;
      const memBar = document.getElementById('memUsedBar');
      memBar.style.width = `${Math.min(100, d.memory.used_percent)}%`;
      setBarColor(memBar, d.memory.used_percent / 100);

      document.getElementById('memFreeVal').textContent = `${d.memory.free_percent.toFixed(1)}%`;
      document.getElementById('memFreeBar').style.width = `${Math.min(100, d.memory.free_percent)}%`;

      document.getElementById('memTotalLine').textContent = `${d.memory.used_formatted} / ${d.memory.total_formatted}`;
      document.getElementById('memCachedLine').textContent = d.memory.cached_formatted;
      document.getElementById('memAvailLine').textContent = d.memory.available_formatted;
    }

    // 4. Root Disk & Physical S.M.A.R.T.
    if (d.disk) {
      document.getElementById('diskUsageVal').textContent = `${d.disk.used_percent.toFixed(1)}%`;
      const diskBar = document.getElementById('diskUsageBar');
      diskBar.style.width = `${Math.min(100, d.disk.used_percent)}%`;
      setBarColor(diskBar, d.disk.used_percent / 100);

      document.getElementById('diskTotalLine').textContent = `${d.disk.total_formatted} · ${d.disk.file_system}`;
      document.getElementById('diskSpaceLine').textContent = `${d.disk.used_formatted} used · ${d.disk.free_formatted} free`;
      document.getElementById('diskSpeedLine').textContent = `Read: ${d.disk.read_speed_formatted} · Write: ${d.disk.write_speed_formatted}`;
    }

    // Physical disk badge
    if (d.physical_disks && d.physical_disks.length > 0) {
      const primary = d.physical_disks[0];
      const smart = primary.smart;
      if (smart) {
        document.getElementById('diskSmartBadge').textContent = `GOOD ${smart.health_percent || 100}%`;
        document.getElementById('diskTempBadge').textContent = smart.temperature_celsius ? `${smart.temperature_celsius}°C` : '--°C';
        document.getElementById('diskSmartQuickLink').textContent = `${primary.model_name} →`;
      }
    }

    // 5. Power / Battery
    if (d.battery) {
      const b = d.battery;
      if (b.installed) {
        document.getElementById('battHealthBadge').textContent = `${b.health_percent.toFixed(1)}%`;
        document.getElementById('battWattsBadge').textContent = b.power_adapter_watts ? `${b.power_adapter_watts}W AC` : (b.is_charging ? 'Charging' : 'Battery');
        document.getElementById('battLevelVal').textContent = `${b.current_capacity_percent}%`;
        
        const battBar = document.getElementById('battLevelBar');
        battBar.style.width = `${Math.min(100, b.current_capacity_percent)}%`;
        if (b.current_capacity_percent < 20) {
          battBar.className = 'bar-fill bar-red';
        } else if (b.current_capacity_percent < 50) {
          battBar.className = 'bar-fill bar-yellow';
        } else {
          battBar.className = 'bar-fill bar-green';
        }

        document.getElementById('battHealthMeterVal').textContent = `${b.health_percent.toFixed(1)}%`;
        document.getElementById('battHealthMeterBar').style.width = `${Math.min(100, b.health_percent)}%`;

        const statusStr = b.is_charging ? 'Charging' : (b.external_connected ? 'AC Power (Idle)' : 'Discharging');
        document.getElementById('battStatusLine').textContent = statusStr;
        const tempStr = b.temperature_celsius ? ` · ${b.temperature_celsius.toFixed(1)}°C` : '';
        document.getElementById('battDetailLine').textContent = `${b.cycle_count} cycles${tempStr}`;
      }
    }

    // 6. Network
    if (d.network) {
      document.getElementById('netIfaceBadge').textContent = d.network.interface_name;
      document.getElementById('netDownVal').textContent = d.network.download_formatted;
      document.getElementById('netUpVal').textContent = d.network.upload_formatted;
      document.getElementById('netIfaceLine').textContent = d.network.local_ip ? `${d.network.interface_name} · ${d.network.local_ip}` : d.network.interface_name;

      netDownHistory.push(d.network.download_bytes_sec);
      if (netDownHistory.length > MAX_HISTORY) netDownHistory.shift();
      drawSparkline(netDownCanvas, netDownHistory, '#a6d189');

      netUpHistory.push(d.network.upload_bytes_sec);
      if (netUpHistory.length > MAX_HISTORY) netUpHistory.shift();
      drawSparkline(netUpCanvas, netUpHistory, '#caa0e6');
    }

    // 7. Top Processes
    if (d.top_processes && d.top_processes.length > 0) {
      const procList = document.getElementById('processList');
      procList.innerHTML = d.top_processes.slice(0, 3).map(p => `
        <div class="proc-row">
          <span class="proc-name" title="${p.name}">${p.name}</span>
          <div class="proc-stats">
            <span class="proc-cpu">${p.cpu_percent.toFixed(0)}%</span>
            <span class="proc-mem">${p.memory_formatted}</span>
          </div>
        </div>
      `).join('');
    }
  }

  function setBarColor(barEl, fraction) {
    barEl.classList.remove('bar-green', 'bar-yellow', 'bar-red');
    if (fraction >= 0.85) {
      barEl.classList.add('bar-red');
    } else if (fraction >= 0.60) {
      barEl.classList.add('bar-yellow');
    } else {
      barEl.classList.add('bar-green');
    }
  }

  function drawSparkline(canvas, data, color) {
    if (!canvas || !data || data.length === 0) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    const max = Math.max(...data, 1.0);
    const step = w / (data.length - 1 || 1);

    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.6;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';

    for (let i = 0; i < data.length; i++) {
      const x = i * step;
      const y = h - (data[i] / max) * (h - 4) - 2;
      if (i === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();

    // Fill under sparkline
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fillStyle = `${color}22`; // ~14% opacity
    ctx.fill();
  }

  // Modals
  function openSmartModal() {
    if (!currentOverview || !currentOverview.physical_disks) return;
    const disks = currentOverview.physical_disks;
    if (disks.length === 0) return;

    // Render disk selector tabs
    const selectorBar = document.getElementById('driveSelectorBar');
    selectorBar.innerHTML = disks.map((d, i) => `
      <button class="drive-tab-btn ${i === activeDriveIndex ? 'active' : ''}" data-index="${i}">
        ${d.id} (${d.model_name.slice(0, 16)})
      </button>
    `).join('');

    selectorBar.querySelectorAll('.drive-tab-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        activeDriveIndex = parseInt(e.target.dataset.index, 10);
        openSmartModal();
      });
    });

    const disk = disks[activeDriveIndex] || disks[0];
    const smart = disk.smart;

    document.getElementById('modalDriveModel').textContent = disk.model_name;
    document.getElementById('modalDriveProto').textContent = disk.protocol;
    document.getElementById('modalDriveSize').textContent = disk.size_formatted;

    if (smart) {
      document.getElementById('modalSmartState').textContent = smart.health_status.toUpperCase();
      document.getElementById('modalSmartPct').textContent = `${smart.health_percent || 100}%`;
      document.getElementById('modalDriveTemp').textContent = smart.temperature_celsius ? `${smart.temperature_celsius}°C` : '--°C';

      document.getElementById('modalDriveTbw').textContent = smart.total_host_writes_tb ? `${smart.total_host_writes_tb.toFixed(1)} TB` : '-- TB';
      document.getElementById('modalDriveReads').textContent = smart.total_host_reads_tb ? `${smart.total_host_reads_tb.toFixed(1)} TB` : '-- TB';
      document.getElementById('modalDriveHours').textContent = smart.power_on_hours ? `${smart.power_on_hours} hours` : '--';

      const tbody = document.getElementById('modalSmartTableBody');
      if (smart.attributes && smart.attributes.length > 0) {
        tbody.innerHTML = smart.attributes.map(a => `
          <tr>
            <td><strong>${a.id}</strong></td>
            <td>${a.name}</td>
            <td>${a.current !== null ? a.current : '-'}</td>
            <td>${a.worst !== null ? a.worst : '-'}</td>
            <td>${a.threshold !== null ? a.threshold : '-'}</td>
            <td><code>${a.raw_hex}</code></td>
            <td class="${a.status === 'Ok' ? 'attr-ok' : 'attr-warn'}">${a.status}</td>
          </tr>
        `).join('');
      } else {
        tbody.innerHTML = `<tr><td colspan="7" style="text-align: center; color: var(--text-dim); padding: 24px;">NVMe Log Page 0x02 healthy. Standard attributes optimal.</td></tr>`;
      }
    }

    smartModal.classList.remove('hidden');
  }

  function openAdvisoryModal() {
    if (!currentOverview || !currentOverview.advisory) return;
    const adv = currentOverview.advisory;

    document.getElementById('advisoryLevel').textContent = adv.level.toUpperCase();
    document.getElementById('advisoryScore').textContent = adv.score;

    const box = document.getElementById('advisoryBadgeBox');
    box.className = 'advisory-badge-box';
    if (adv.level === 'Critical' || adv.level === 'Recommended') {
      box.classList.add('critical');
    } else if (adv.level === 'Optimal') {
      box.classList.add('optimal');
    }

    document.getElementById('advisorySummaryHeading').textContent = adv.should_reboot ? 'Reboot Recommended' : 'System Performance Status';
    document.getElementById('advisorySummaryText').textContent = adv.summary;
    document.getElementById('advisorySwapVal').textContent = adv.swap_used_formatted;
    document.getElementById('advisoryUptimeVal').textContent = `${adv.uptime_days} days`;

    const triggersList = document.getElementById('triggersList');
    if (adv.triggers && adv.triggers.length > 0) {
      triggersList.innerHTML = adv.triggers.map(t => `
        <div class="trigger-item ${t.severity === 'critical' ? 'critical' : ''}">
          <span class="trigger-icon">${t.severity === 'critical' ? '⚠️' : 'ℹ️'}</span>
          <div class="trigger-content">
            <div class="trigger-title">${t.category} (${t.metric_value})</div>
            <div class="trigger-msg">${t.message}</div>
          </div>
        </div>
      `).join('');
    } else {
      triggersList.innerHTML = `<div style="padding: 12px; color: var(--text-dim); text-align: center;">No hardware degradation bottlenecks detected.</div>`;
    }

    advisoryModal.classList.remove('hidden');
  }

  async function openReportModal() {

    reportModal.classList.remove('hidden');
    try {
      const res = await fetch('/api/report');
      if (res.ok) {
        const text = await res.text();
        reportText.value = text;
      }
    } catch (err) {
      reportText.value = 'Failed to generate report.';
    }
  }

  document.addEventListener('DOMContentLoaded', init);
})();
