const express = require('express');
const { exec, execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const app = express();

// 项目根目录（web 的上级目录，脚本和配置文件所在位置）
const PROJECT_ROOT = path.resolve(__dirname, '..');
const CONF_FILE = path.join(PROJECT_ROOT, 'meds.conf');
const MED_CONF = path.join(PROJECT_ROOT, 'med.conf');
const MY_CRON = path.join(PROJECT_ROOT, 'my_cron');
const HISTORY_LOG = path.join(PROJECT_ROOT, 'log', 'med_history.log');
const LOG_DIR = path.join(PROJECT_ROOT, 'log');
const SCRIPTS = {
    daemon: path.join(PROJECT_ROOT, 'background_daemon.sh'),
    guardian: path.join(PROJECT_ROOT, 'guardian.sh'),
    remind: path.join(PROJECT_ROOT, 'remind.sh'),
    parser: path.join(PROJECT_ROOT, 'parser.sh'),
    sync: path.join(PROJECT_ROOT, 'sync_schedule.sh'),
    audit: path.join(PROJECT_ROOT, 'audit_report.sh'),
    logCleaner: path.join(PROJECT_ROOT, 'log_cleaner.sh'),
};

app.use(express.json());
app.use(express.static(__dirname, { maxAge: 0 }));

// 确保日志目录存在
try { fs.mkdirSync(LOG_DIR, { recursive: true }); } catch (_) {}

// ── 工具函数 ──────────────────────────────────────────────

/** 读取 meds.conf，返回 [{ name, time }, ...] */
function readMedsConf() {
    if (!fs.existsSync(CONF_FILE)) return [];
    const content = fs.readFileSync(CONF_FILE, 'utf8');
    return content
        .split('\n')
        .map(l => l.trim())
        .filter(l => l && !l.startsWith('#'))
        .map(line => {
            const parts = line.split(/\s+/);
            return { name: parts.slice(0, -1).join(' ') || parts[0], time: parts[parts.length - 1] };
        });
}

/** 写入 meds.conf */
function writeMedsConf(medications) {
    const content = medications.map(m => `${m.name} ${m.time}`).join('\n') + '\n';
    fs.writeFileSync(CONF_FILE, content, 'utf8');
}

/** 执行 shell 命令，返回 Promise */
function runCmd(cmd, opts = {}) {
    return new Promise((resolve, reject) => {
        exec(cmd, { cwd: PROJECT_ROOT, ...opts }, (err, stdout, stderr) => {
            if (err) return reject(err);
            resolve({ stdout: stdout.trim(), stderr: stderr.trim() });
        });
    });
}

/** 跨平台进程检测 */
function isProcessRunning(scriptName) {
    try {
        const isWin = os.platform() === 'win32';
        if (isWin) {
            const out = execSync(`tasklist /FI "IMAGENAME eq bash.exe" 2>nul`, { encoding: 'utf8' });
            return out.includes('bash.exe');
        }
        const out = execSync(`ps aux | grep -v grep | grep -F "${scriptName}" | wc -l`, { encoding: 'utf8' });
        return parseInt(out.trim(), 10) > 0;
    } catch {
        return false;
    }
}

/** 跨平台磁盘使用率 */
function getDiskUsage() {
    try {
        const isWin = os.platform() === 'win32';
        if (isWin) {
            const drive = PROJECT_ROOT.slice(0, 2) || 'C:';
            const out = execSync(`wmic logicaldisk where "DeviceID='${drive}'" get Size,FreeSpace /format:csv 2>nul`, { encoding: 'utf8', timeout: 5000 });
            const lines = out.trim().split('\n');
            if (lines.length < 2) return { usage: 'N/A', used: 'N/A', avail: 'N/A' };
            const [, free, total] = lines[1].split(',');
            const freeBytes = parseInt(free, 10);
            const totalBytes = parseInt(total, 10);
            if (!totalBytes) return { usage: 'N/A', used: 'N/A', avail: 'N/A' };
            const usedBytes = totalBytes - freeBytes;
            const pct = Math.round((usedBytes / totalBytes) * 100) + '%';
            const usedGB = (usedBytes / 1073741824).toFixed(1) + 'G';
            const availGB = (freeBytes / 1073741824).toFixed(1) + 'G';
            return { usage: pct, used: usedGB, avail: availGB };
        }
        const out = execSync(`df -h "${PROJECT_ROOT}" | awk 'NR==2 {print $5, $3, $4}'`, { encoding: 'utf8', timeout: 5000 });
        const parts = out.trim().split(/\s+/);
        return { usage: parts[0] || 'N/A', used: parts[1] || 'N/A', avail: parts[2] || 'N/A' };
    } catch {
        return { usage: 'N/A', used: 'N/A', avail: 'N/A' };
    }
}

// ── 药品管理 API ──────────────────────────────────────────

// 获取所有药品列表
app.get('/api/medications', (_req, res, next) => {
    try {
        const meds = readMedsConf();
        res.json({ success: true, data: meds });
    } catch (e) { next(e); }
});

// 添加药品
app.post('/api/medications', (req, res, next) => {
    try {
        const { name, time } = req.body;
        if (!name || !time) {
            return res.status(400).json({ success: false, message: '药品名和时间不能为空' });
        }
        if (!/^\d{2}:\d{2}$/.test(time)) {
            return res.status(400).json({ success: false, message: '时间格式必须为 HH:MM' });
        }
        const meds = readMedsConf();
        if (meds.some(m => m.name === name)) {
            return res.status(400).json({ success: false, message: `药品 "${name}" 已存在` });
        }
        meds.push({ name, time });
        writeMedsConf(meds);
        res.json({ success: true, message: '添加成功' });
    } catch (e) { next(e); }
});

// 更新药品时间
app.put('/api/medications/:name', (req, res, next) => {
    try {
        const { time } = req.body;
        if (!time || !/^\d{2}:\d{2}$/.test(time)) {
            return res.status(400).json({ success: false, message: '时间格式必须为 HH:MM' });
        }
        const meds = readMedsConf();
        const idx = meds.findIndex(m => m.name === req.params.name);
        if (idx === -1) {
            return res.status(404).json({ success: false, message: '药品不存在' });
        }
        meds[idx].time = time;
        writeMedsConf(meds);
        res.json({ success: true, message: '更新成功' });
    } catch (e) { next(e); }
});

// 删除药品
app.delete('/api/medications/:name', (req, res, next) => {
    try {
        const meds = readMedsConf();
        const filtered = meds.filter(m => m.name !== req.params.name);
        if (filtered.length === meds.length) {
            return res.status(404).json({ success: false, message: '药品不存在' });
        }
        writeMedsConf(filtered);
        res.json({ success: true, message: '删除成功' });
    } catch (e) { next(e); }
});

// ── 时间设置 API（兼容旧接口）─────────────────────────────

app.post('/api/set-time', (req, res, next) => {
    try {
        const { name, time } = req.body;
        if (!name) {
            const meds = readMedsConf();
            if (meds.length === 0) {
                return res.status(400).json({ success: false, message: '没有药品可更新' });
            }
            meds.forEach(m => { m.time = time; });
            writeMedsConf(meds);
            return res.json({ success: true, message: `已将全部 ${meds.length} 种药品时间更新为 ${time}` });
        }
        const meds = readMedsConf();
        const idx = meds.findIndex(m => m.name === name);
        if (idx === -1) {
            meds.push({ name, time });
        } else {
            meds[idx].time = time;
        }
        writeMedsConf(meds);
        res.json({ success: true, message: '设置成功' });
    } catch (e) { next(e); }
});

// ── 服药记录 API ──────────────────────────────────────────

// 获取服药历史记录
app.get('/api/get-records', (_req, res, next) => {
    try {
        if (!fs.existsSync(HISTORY_LOG)) {
            return res.json({ success: true, data: [] });
        }
        const data = fs.readFileSync(HISTORY_LOG, 'utf8');
        const lines = data.split('\n').filter(l => l.trim());
        res.json({ success: true, data: lines });
    } catch (e) { next(e); }
});

// 标记已服药
app.post('/api/take-medication', (req, res, next) => {
    try {
        const { name, time } = req.body;
        if (!name) {
            return res.status(400).json({ success: false, message: '药品名不能为空' });
        }
        const now = new Date();
        const dateStr = now.toISOString().split('T')[0];
        const timeStr = time || now.toTimeString().slice(0, 5);
        const record = `[${dateStr} ${timeStr}] ${name} - 已服`;
        fs.appendFileSync(HISTORY_LOG, record + '\n', 'utf8');
        res.json({ success: true, message: '记录成功', record });
    } catch (e) { next(e); }
});

// 清空服药记录
app.delete('/api/clear-records', (_req, res, next) => {
    try {
        fs.writeFileSync(HISTORY_LOG, '', 'utf8');
        res.json({ success: true, message: '记录已清空' });
    } catch (e) { next(e); }
});

// ── 服药统计 API ──────────────────────────────────────────

app.get('/api/audit', (_req, res, next) => {
    try {
        if (!fs.existsSync(HISTORY_LOG)) {
            return res.json({ success: true, data: { total: 0, taken: 0, rate: '0.00%' } });
        }
        const data = fs.readFileSync(HISTORY_LOG, 'utf8');
        const lines = data.split('\n').filter(l => l.trim());
        const total = lines.length;
        const taken = lines.filter(l => l.includes('已服')).length;
        const rate = total > 0 ? ((taken / total) * 100).toFixed(2) + '%' : '0.00%';
        res.json({ success: true, data: { total, taken, rate } });
    } catch (e) { next(e); }
});

// ── 系统状态 API（跨平台）─────────────────────────────────

app.get('/api/status', (_req, res, next) => {
    try {
        const services = {
            daemon: isProcessRunning('background_daemon.sh'),
            guardian: isProcessRunning('guardian.sh'),
            remind: isProcessRunning('remind.sh'),
            parser: isProcessRunning('parser.sh'),
        };

        const disk = getDiskUsage();

        // 日志大小
        let logSize = '0 B';
        if (fs.existsSync(HISTORY_LOG)) {
            const stat = fs.statSync(HISTORY_LOG);
            logSize = stat.size > 1048576
                ? (stat.size / 1048576).toFixed(2) + ' MB'
                : stat.size > 1024
                    ? (stat.size / 1024).toFixed(1) + ' KB'
                    : stat.size + ' B';
        }

        const medCount = readMedsConf().length;

        res.json({
            success: true,
            data: { services, diskUsage: disk.usage, diskUsed: disk.used, diskAvail: disk.avail, logSize, medicationCount: medCount, platform: os.platform(), hostname: os.hostname() }
        });
    } catch (e) { next(e); }
});

// ── 服务控制 API ──────────────────────────────────────────

app.post('/api/service/:action', (req, res, next) => {
    const { action } = req.params;
    const { service } = req.body;

    const validServices = ['daemon', 'guardian', 'remind', 'parser'];
    if (!validServices.includes(service)) {
        return res.status(400).json({ success: false, message: `无效的服务名，可选: ${validServices.join(', ')}` });
    }

    const scriptPath = SCRIPTS[service];
    const scriptName = path.basename(scriptPath);
    const logFile = path.join(LOG_DIR, `${service}.log`);

    // 非 Linux 平台不支持服务管理
    if (os.platform() !== 'linux') {
        return res.json({ success: false, message: `服务管理仅支持 Linux 环境，当前平台: ${os.platform()}` });
    }

    try {
        switch (action) {
            case 'start': {
                if (isProcessRunning(scriptName)) {
                    return res.json({ success: true, message: `${service} 服务已在运行中` });
                }
                spawn('bash', [scriptPath], {
                    cwd: PROJECT_ROOT,
                    detached: true,
                    stdio: ['ignore', fs.openSync(logFile, 'a'), fs.openSync(logFile, 'a')]
                }).unref();
                res.json({ success: true, message: `${service} 服务已启动` });
                break;
            }
            case 'stop': {
                exec(`pkill -f "${scriptName}"`, { cwd: PROJECT_ROOT }, (err) => {
                    if (err) return res.json({ success: true, message: `${service} 服务已停止（或未在运行）` });
                    res.json({ success: true, message: `${service} 服务已停止` });
                });
                break;
            }
            case 'restart': {
                exec(`pkill -f "${scriptName}"`, { cwd: PROJECT_ROOT }, () => {
                    spawn('bash', [scriptPath], {
                        cwd: PROJECT_ROOT,
                        detached: true,
                        stdio: ['ignore', fs.openSync(logFile, 'a'), fs.openSync(logFile, 'a')]
                    }).unref();
                });
                res.json({ success: true, message: `${service} 服务正在重启中` });
                break;
            }
            default:
                res.status(400).json({ success: false, message: '无效操作，可选: start, stop, restart' });
        }
    } catch (e) { next(e); }
});

// ── 日志查看 API ──────────────────────────────────────────

app.get('/api/logs/:type', (req, res, next) => {
    const { type } = req.params;
    const validTypes = ['daemon', 'guardian', 'remind', 'parser', 'background', 'med_history'];
    if (!validTypes.includes(type)) {
        return res.status(400).json({ success: false, message: `无效的日志类型，可选: ${validTypes.join(', ')}` });
    }

    const logFileMap = {
        daemon: 'background.log',
        guardian: 'guardian.log',
        remind: 'remind.log',
        parser: 'background.log',
        background: 'background.log',
        med_history: 'med_history.log',
    };

    const logPath = path.join(LOG_DIR, logFileMap[type]);
    const lines = parseInt(req.query.lines, 10) || 100;

    try {
        if (!fs.existsSync(logPath)) {
            return res.json({ success: true, data: [], total: 0 });
        }
        const content = fs.readFileSync(logPath, 'utf8');
        const allLines = content.split('\n').filter(l => l.trim());
        const recent = allLines.slice(-lines);
        res.json({ success: true, data: recent, total: allLines.length });
    } catch (e) { next(e); }
});

// ── 计划同步 API ──────────────────────────────────────────

app.post('/api/sync-schedule', async (req, res, next) => {
    try {
        const result = await runCmd(`bash "${SCRIPTS.sync}"`);
        res.json({ success: true, message: '同步成功', output: result.stdout });
    } catch (e) { next(e); }
});

// 获取当前 cron 配置
app.get('/api/cron', (_req, res, next) => {
    try {
        if (!fs.existsSync(MY_CRON)) {
            return res.json({ success: true, data: [] });
        }
        const content = fs.readFileSync(MY_CRON, 'utf8');
        const lines = content.split('\n').filter(l => l.trim());
        res.json({ success: true, data: lines });
    } catch (e) { next(e); }
});

// ── 日志清理 API ──────────────────────────────────────────

app.post('/api/clean-logs', async (req, res, next) => {
    try {
        await runCmd(`bash "${SCRIPTS.logCleaner}"`);
        res.json({ success: true, message: '日志清理检查完成' });
    } catch (e) { next(e); }
});

// ── 全局错误处理中间件 ────────────────────────────────────

app.use((err, _req, res, _next) => {
    console.error(`[${new Date().toISOString()}] 服务端错误:`, err.message || err);
    res.status(500).json({ success: false, message: err.message || '服务器内部错误' });
});

// ── 启动服务 ──────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
    console.log(`[${new Date().toISOString()}] 智能服药提醒系统 Web 服务已启动`);
    console.log(`  本地访问: http://localhost:${PORT}`);
    console.log(`  项目目录: ${PROJECT_ROOT}`);
    console.log(`  运行平台: ${os.platform()}`);
});
