/**
 * 系统管理模块 API 测试套件
 *
 * 覆盖端点：
 *   GET  /api/status            — 系统状态
 *   GET  /api/logs/:type        — 日志查看
 *   GET  /api/reminder-status   — 提醒调度状态
 *   GET  /api/cron              — cron 配置
 *   GET  /api/audit             — 服药统计
 *   GET  /api/medications       — 药品列表
 *   POST /api/medications       — 添加药品
 *   PUT  /api/medications/:name — 更新药品
 *   DELETE /api/medications/:name — 删除药品
 *   POST /api/set-time          — 批量设置时间
 *   POST /api/take-medication   — 服药记录
 *   GET  /api/get-records       — 获取记录
 *   DELETE /api/clear-records   — 清空记录
 *   POST /api/sync-schedule     — 同步计划
 *   POST /api/clean-logs        — 日志清理
 *   POST /api/service/:action   — 服务控制
 *
 * 运行: npx jest web/__tests__/app.test.js
 */

const fs = require('fs');
const path = require('path');

// ── Mock child_process ──────────────────────────────────────
const mockExec = jest.fn((cmd, opts, cb) => {
    if (typeof opts === 'function') { cb = opts; }
    if (cb) cb(null, 'mock stdout', '');
});
const mockExecSync = jest.fn(() => Buffer.from(''));
const mockSpawn = jest.fn(() => ({ unref: jest.fn() }));

jest.mock('child_process', () => ({
    exec: mockExec,
    execSync: mockExecSync,
    spawn: mockSpawn,
}));

// ── 加载被测模块 ────────────────────────────────────────────
const app = require('../app');

// ── 辅助: 测试文件路径 ──────────────────────────────────────
const PROJECT_ROOT = path.resolve(__dirname, '../..');
const CONF_FILE = path.join(PROJECT_ROOT, 'meds.conf');
const MED_CONF = path.join(PROJECT_ROOT, 'med.conf');
const MY_CRON = path.join(PROJECT_ROOT, 'my_cron');
const HISTORY_LOG = path.join(PROJECT_ROOT, 'log', 'med_history.log');
const LOG_DIR = path.join(PROJECT_ROOT, 'log');

// ── 备份/恢复 ───────────────────────────────────────────────
let confBackup = null;
let medConfBackup = null;
let cronBackup = null;
let historyBackup = null;

beforeAll(() => {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    if (fs.existsSync(CONF_FILE)) confBackup = fs.readFileSync(CONF_FILE, 'utf8');
    if (fs.existsSync(MED_CONF)) medConfBackup = fs.readFileSync(MED_CONF, 'utf8');
    if (fs.existsSync(MY_CRON)) cronBackup = fs.readFileSync(MY_CRON, 'utf8');
    if (fs.existsSync(HISTORY_LOG)) historyBackup = fs.readFileSync(HISTORY_LOG, 'utf8');
});

afterAll(() => {
    if (confBackup !== null) fs.writeFileSync(CONF_FILE, confBackup, 'utf8'); else try { fs.unlinkSync(CONF_FILE); } catch {}
    if (medConfBackup !== null) fs.writeFileSync(MED_CONF, medConfBackup, 'utf8'); else try { fs.unlinkSync(MED_CONF); } catch {}
    if (cronBackup !== null) fs.writeFileSync(MY_CRON, cronBackup, 'utf8'); else try { fs.unlinkSync(MY_CRON); } catch {}
    if (historyBackup !== null) fs.writeFileSync(HISTORY_LOG, historyBackup, 'utf8'); else try { fs.unlinkSync(HISTORY_LOG); } catch {}
});

beforeEach(() => {
    fs.writeFileSync(CONF_FILE, '', 'utf8');
    fs.writeFileSync(HISTORY_LOG, '', 'utf8');
    mockExec.mockClear();
    mockExecSync.mockClear();
    mockSpawn.mockClear();
});

// ═══════════════════════════════════════════════════════════════
// 系统状态
// ═══════════════════════════════════════════════════════════════
describe('GET /api/status', () => {
    it('返回 success:true 和完整的系统状态字段', async () => {
        const request = require('supertest');
        const res = await request(app).get('/api/status');
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data).toMatchObject({
            services: {
                daemon: expect.any(Boolean),
                guardian: expect.any(Boolean),
                remind: expect.any(Boolean),
                parser: expect.any(Boolean),
            },
            diskUsage: expect.any(String),
            diskUsed: expect.any(String),
            diskAvail: expect.any(String),
            logSize: expect.any(String),
            medicationCount: expect.any(Number),
            platform: expect.any(String),
            hostname: expect.any(String),
        });
    });

    it('无药品时 medicationCount 为 0', async () => {
        fs.writeFileSync(CONF_FILE, '', 'utf8');
        const request = require('supertest');
        const res = await request(app).get('/api/status');
        expect(res.body.data.medicationCount).toBe(0);
    });
});

// ═══════════════════════════════════════════════════════════════
// 日志查看
// ═══════════════════════════════════════════════════════════════
describe('GET /api/logs/:type', () => {
    it('daemon 类型返回日志数组和总数', async () => {
        const request = require('supertest');
        const res = await request(app).get('/api/logs/daemon?lines=10');
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(typeof res.body.total).toBe('number');
    });

    it('无效日志类型返回 400', async () => {
        const request = require('supertest');
        const res = await request(app).get('/api/logs/invalid_type');
        expect(res.status).toBe(400);
        expect(res.body.success).toBe(false);
    });

    const types = ['guardian', 'remind', 'parser', 'background', 'med_history'];
    types.forEach((type) => {
        it(`${type} 类型返回 200`, async () => {
            const request = require('supertest');
            const res = await request(app).get(`/api/logs/${type}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });
    });

    it('支持 lines 参数限制行数', async () => {
        // 写入超过 5 行的日志
        const logPath = path.join(LOG_DIR, 'background.log');
        const orig = fs.existsSync(logPath) ? fs.readFileSync(logPath, 'utf8') : '';
        fs.writeFileSync(logPath, Array.from({ length: 20 }, (_, i) => `line ${i + 1}`).join('\n'), 'utf8');

        const request = require('supertest');
        const res = await request(app).get('/api/logs/daemon?lines=5');
        expect(res.body.data.length).toBeLessThanOrEqual(5);

        fs.writeFileSync(logPath, orig, 'utf8');
    });
});

// ═══════════════════════════════════════════════════════════════
// 提醒调度状态
// ═══════════════════════════════════════════════════════════════
describe('GET /api/reminder-status', () => {
    it('空配置时返回空药品列表', async () => {
        fs.writeFileSync(CONF_FILE, '', 'utf8');
        const request = require('supertest');
        const res = await request(app).get('/api/reminder-status');
        expect(res.status).toBe(200);
        expect(res.body.success).toBe(true);
        expect(res.body.data.medications).toEqual([]);
    });

    it('有药品时返回含 nextTrigger 的列表', async () => {
        fs.writeFileSync(CONF_FILE, '阿司匹林 09:30\n', 'utf8');
        const request = require('supertest');
        const res = await request(app).get('/api/reminder-status');
        expect(res.status).toBe(200);
        expect(res.body.data.medications).toHaveLength(1);
        expect(res.body.data.medications[0]).toMatchObject({
            name: '阿司匹林',
            time: '09:30',
            nextTrigger: expect.any(String),
            minutesUntil: expect.any(Number),
        });
    });
});

// ═══════════════════════════════════════════════════════════════
// Cron 配置
// ═══════════════════════════════════════════════════════════════
describe('GET /api/cron', () => {
    it('my_cron 不存在时返回空数组', async () => {
        const origExists = fs.existsSync(MY_CRON);
        const origContent = origExists ? fs.readFileSync(MY_CRON, 'utf8') : null;
        if (origExists) fs.unlinkSync(MY_CRON);

        const request = require('supertest');
        const res = await request(app).get('/api/cron');
        expect(res.status).toBe(200);
        expect(res.body.data).toEqual([]);

        if (origContent !== null) fs.writeFileSync(MY_CRON, origContent, 'utf8');
    });

    it('my_cron 存在时返回内容行数组', async () => {
        fs.writeFileSync(MY_CRON, '0 8 * * * /path/to/notify.sh 维生素C\n', 'utf8');
        const request = require('supertest');
        const res = await request(app).get('/api/cron');
        expect(res.status).toBe(200);
        expect(res.body.data).toHaveLength(1);
        fs.writeFileSync(MY_CRON, '', 'utf8');
    });
});

// ═══════════════════════════════════════════════════════════════
// 服药统计
// ═══════════════════════════════════════════════════════════════
describe('GET /api/audit', () => {
    it('无历史记录时返回 0 统计', async () => {
        fs.writeFileSync(HISTORY_LOG, '', 'utf8');
        const request = require('supertest');
        const res = await request(app).get('/api/audit');
        expect(res.status).toBe(200);
        expect(res.body.data).toEqual({ total: 0, taken: 0, rate: '0.00%' });
    });

    it('正确统计已服和总数', async () => {
        fs.writeFileSync(HISTORY_LOG, [
            '[2025-06-01 08:00] 维生素C - 已服',
            '[2025-06-01 14:00] 降压药 - 未服',
            '[2025-06-01 20:00] 复合维生素 - 已服',
        ].join('\n'), 'utf8');
        const request = require('supertest');
        const res = await request(app).get('/api/audit');
        expect(res.body.data.total).toBe(3);
        expect(res.body.data.taken).toBe(2);
        expect(res.body.data.rate).toBe('66.67%');
    });
});

// ═══════════════════════════════════════════════════════════════
// 药品 CRUD
// ═══════════════════════════════════════════════════════════════
describe('药品管理 API', () => {
    describe('GET /api/medications', () => {
        it('空配置返回空数组', async () => {
            fs.writeFileSync(CONF_FILE, '', 'utf8');
            const request = require('supertest');
            const res = await request(app).get('/api/medications');
            expect(res.status).toBe(200);
            expect(res.body.data).toEqual([]);
        });

        it('返回所有药品', async () => {
            fs.writeFileSync(CONF_FILE, '维生素C 08:00\n降压药 14:00\n', 'utf8');
            const request = require('supertest');
            const res = await request(app).get('/api/medications');
            expect(res.body.data).toHaveLength(2);
            expect(res.body.data[0]).toMatchObject({ name: '维生素C', time: '08:00' });
        });
    });

    describe('POST /api/medications', () => {
        it('成功添加药品', async () => {
            fs.writeFileSync(CONF_FILE, '', 'utf8');
            const request = require('supertest');
            const res = await request(app)
                .post('/api/medications')
                .send({ name: '阿司匹林', time: '09:30' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            // 确认写入文件
            const content = fs.readFileSync(CONF_FILE, 'utf8');
            expect(content).toContain('阿司匹林 09:30');
        });

        it('缺少 name 返回 400', async () => {
            const request = require('supertest');
            const res = await request(app)
                .post('/api/medications')
                .send({ time: '09:30' });
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
        });

        it('时间格式非法返回 400', async () => {
            const request = require('supertest');
            const res = await request(app)
                .post('/api/medications')
                .send({ name: '测试药', time: 'abc' });
            expect(res.status).toBe(400);
        });

        it('重复药品名返回 400', async () => {
            fs.writeFileSync(CONF_FILE, '阿司匹林 08:00\n', 'utf8');
            const request = require('supertest');
            const res = await request(app)
                .post('/api/medications')
                .send({ name: '阿司匹林', time: '10:00' });
            expect(res.status).toBe(400);
        });
    });

    describe('PUT /api/medications/:name', () => {
        it('更新已有药品时间', async () => {
            fs.writeFileSync(CONF_FILE, '阿司匹林 08:00\n', 'utf8');
            const request = require('supertest');
            const res = await request(app)
                .put('/api/medications/阿司匹林')
                .send({ time: '10:30' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            const content = fs.readFileSync(CONF_FILE, 'utf8');
            expect(content).toContain('阿司匹林 10:30');
        });

        it('药品不存在返回 404', async () => {
            fs.writeFileSync(CONF_FILE, '', 'utf8');
            const request = require('supertest');
            const res = await request(app)
                .put('/api/medications/不存在')
                .send({ time: '10:00' });
            expect(res.status).toBe(404);
        });
    });

    describe('DELETE /api/medications/:name', () => {
        it('删除已有药品', async () => {
            fs.writeFileSync(CONF_FILE, '阿司匹林 08:00\n维生素C 14:00\n', 'utf8');
            const request = require('supertest');
            const res = await request(app).delete('/api/medications/阿司匹林');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            const content = fs.readFileSync(CONF_FILE, 'utf8');
            expect(content).not.toContain('阿司匹林');
            expect(content).toContain('维生素C');
        });

        it('药品不存在返回 404', async () => {
            fs.writeFileSync(CONF_FILE, '', 'utf8');
            const request = require('supertest');
            const res = await request(app).delete('/api/medications/不存在');
            expect(res.status).toBe(404);
        });
    });
});

// ═══════════════════════════════════════════════════════════════
// 批量设置时间
// ═══════════════════════════════════════════════════════════════
describe('POST /api/set-time', () => {
    it('不带 name 时批量更新所有药品时间', async () => {
        fs.writeFileSync(CONF_FILE, '药A 08:00\n药B 14:00\n', 'utf8');
        const request = require('supertest');
        const res = await request(app)
            .post('/api/set-time')
            .send({ time: '12:00' });
        expect(res.status).toBe(200);
        const lines = fs.readFileSync(CONF_FILE, 'utf8').trim().split('\n');
        lines.forEach((line) => {
            expect(line).toMatch(/12:00$/);
        });
    });

    it('带 name 时更新或创建该药品', async () => {
        fs.writeFileSync(CONF_FILE, '', 'utf8');
        const request = require('supertest');
        const res = await request(app)
            .post('/api/set-time')
            .send({ name: '新药', time: '08:30' });
        expect(res.status).toBe(200);
        expect(fs.readFileSync(CONF_FILE, 'utf8')).toContain('新药 08:30');
    });

    it('无药品且无 name 时返回 400', async () => {
        fs.writeFileSync(CONF_FILE, '', 'utf8');
        const request = require('supertest');
        const res = await request(app)
            .post('/api/set-time')
            .send({ time: '12:00' });
        expect(res.status).toBe(400);
    });
});

// ═══════════════════════════════════════════════════════════════
// 服药记录
// ═══════════════════════════════════════════════════════════════
describe('服药记录 API', () => {
    describe('POST /api/take-medication', () => {
        it('记录服药', async () => {
            fs.writeFileSync(HISTORY_LOG, '', 'utf8');
            const request = require('supertest');
            const res = await request(app)
                .post('/api/take-medication')
                .send({ name: '维生素C' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.record).toContain('维生素C - 已服');
        });

        it('缺少 name 返回 400', async () => {
            const request = require('supertest');
            const res = await request(app)
                .post('/api/take-medication')
                .send({});
            expect(res.status).toBe(400);
        });
    });

    describe('GET /api/get-records', () => {
        it('返回历史记录数组', async () => {
            fs.writeFileSync(HISTORY_LOG, '记录1\n记录2\n', 'utf8');
            const request = require('supertest');
            const res = await request(app).get('/api/get-records');
            expect(res.status).toBe(200);
            expect(res.body.data).toHaveLength(2);
        });
    });

    describe('DELETE /api/clear-records', () => {
        it('清空记录', async () => {
            fs.writeFileSync(HISTORY_LOG, '记录1\n', 'utf8');
            const request = require('supertest');
            const res = await request(app).delete('/api/clear-records');
            expect(res.status).toBe(200);
            expect(fs.readFileSync(HISTORY_LOG, 'utf8')).toBe('');
        });
    });
});

// ═══════════════════════════════════════════════════════════════
// 系统管理操作 API
// ═══════════════════════════════════════════════════════════════
describe('系统管理操作 API', () => {
    describe('POST /api/sync-schedule', () => {
        it('同步成功后返回 success', async () => {
            mockExec.mockImplementationOnce((cmd, opts, cb) => {
                if (typeof opts === 'function') { cb = opts; }
                if (cb) cb(null, '定时任务已解析并保存到 my_cron', '');
            });
            const request = require('supertest');
            const res = await request(app).post('/api/sync-schedule');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });

        it('脚本执行失败时返回 500', async () => {
            mockExec.mockImplementationOnce((cmd, opts, cb) => {
                if (typeof opts === 'function') { cb = opts; }
                if (cb) cb(new Error('脚本错误'), '', 'stderr');
            });
            const request = require('supertest');
            const res = await request(app).post('/api/sync-schedule');
            expect(res.status).toBe(500);
        });
    });

    describe('POST /api/clean-logs', () => {
        it('清理完成后返回 success', async () => {
            mockExec.mockImplementationOnce((cmd, opts, cb) => {
                if (typeof opts === 'function') { cb = opts; }
                if (cb) cb(null, '', '');
            });
            const request = require('supertest');
            const res = await request(app).post('/api/clean-logs');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });
    });

    describe('POST /api/service/:action', () => {
        it('非 Linux 平台返回不支持', async () => {
            const request = require('supertest');
            const res = await request(app)
                .post('/api/service/start')
                .send({ service: 'daemon' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(false);
            expect(res.body.message).toContain('仅支持 Linux');
        });

        it('无效服务名返回 400', async () => {
            const request = require('supertest');
            const res = await request(app)
                .post('/api/service/start')
                .send({ service: 'invalid' });
            expect(res.status).toBe(400);
        });

        it('无效操作在非 Linux 平台被平台检查先拦截', async () => {
            // 非 Linux 平台上，平台检查先于 action 校验执行，返回 200 + success:false
            const request = require('supertest');
            const res = await request(app)
                .post('/api/service/unknown')
                .send({ service: 'daemon' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(false);
            expect(res.body.message).toContain('仅支持 Linux');
        });
    });
});
