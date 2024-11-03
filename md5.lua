-- taken from https://github.com/rkscv/danmaku/blob/main/danmaku.lua
-- modified from https://bitop.luajit.org/download.html (LuaBitOp-1.0.2 / md5test.lua)
-- and https://github.com/kikito/md5.lua/blob/master/md5.lua
-- SPDX-License-Identifier:MIT

local byte, char, sub, rep = string.byte, string.char, string.sub, string.rep

local tobit, tohex, bnot, bor, band, bxor, lshift, rshift, rol, bswap
local ok, bit = pcall(require, 'bit')  --LuaJIT
if ok then
    tobit, tohex = bit.tobit or bit.cast, bit.tohex
    bnot, bor, band, bxor, lshift, rshift = bit.bnot, bit.bor, bit.band, bit.bxor, bit.lshift, bit.rshift
    rol, bswap = bit.rol, bit.bswap
else
    local ok, bit = pcall(require, 'bit32')  --Lua 5.2
    if ok then
        local bit32_bnot = bit.bnot
        tobit = function(a) return a <= 0x7fffffff and a or -(bit32_bnot(a) + 1) end
        bnot = function(a) return tobit(bit32_bnot(tobit(a))) end
        bor, band, bxor, lshift, rshift, rol = bit.bor, bit.band, bit.bxor, bit.lshift, bit.rshift, bit.lrotate
    else  --Lua 5.1
        local function tbl2number(tbl)
            local result = 0
            local power = 1
            for i = 1, #tbl do
                result = result + tbl[i] * power
                power = power * 2
            end
            return result
        end

        local function expand(t1, t2)
            local big, small = t1, t2
            if #big < #small then
                big, small = small, big
            end
            -- expand small
            for i = #small + 1, #big do
                small[i] = 0
            end
        end

        local tobit -- needs to be declared before bnot

        bnot = function(n)
            local tbl = tobit(n)
            local size = math.max(#tbl, 32)
            for i = 1, size do
                if tbl[i] == 1 then
                    tbl[i] = 0
                else
                    tbl[i] = 1
                end
            end
            return tbl2number(tbl)
        end

        -- defined as local above
        tobit = function (n)
            if n < 0 then
                -- negative
                return tobit(bnot(math.abs(n)) + 1)
            end
            -- to bits table
            local tbl = {}
            local cnt = 1
            local last
            while n > 0 do
                last = n % 2
                tbl[cnt] = last
                n = (n - last) / 2
                cnt = cnt + 1
            end
            return tbl
        end

        bor = function(m, n)
            local tbl_m = tobit(m)
            local tbl_n = tobit(n)
            expand(tbl_m, tbl_n)
            local tbl = {}
            for i = 1, #tbl_m do
                if tbl_m[i] == 0 and tbl_n[i] == 0 then
                    tbl[i] = 0
                else
                    tbl[i] = 1
                end
            end
            return tbl2number(tbl)
        end

        band = function(m, n)
            local tbl_m = tobit(m)
            local tbl_n = tobit(n)
            expand(tbl_m, tbl_n)
            local tbl = {}
            for i = 1, #tbl_m do
                if tbl_m[i] == 0 or tbl_n[i] == 0 then
                    tbl[i] = 0
                else
                    tbl[i] = 1
                end
            end
            return tbl2number(tbl)
        end

        bxor = function(m, n)
            local tbl_m = tobit(m)
            local tbl_n = tobit(n)
            expand(tbl_m, tbl_n)
            local tbl = {}
            for i = 1, #tbl_m do
                if tbl_m[i] ~= tbl_n[i] then
                    tbl[i] = 1
                else
                    tbl[i] = 0
                end
            end
            return tbl2number(tbl)
        end

        lshift = function(n, bits)
            if n < 0 then
                -- negative
                n = bnot(math.abs(n)) + 1
            end
            for i = 1, bits do
                n = n * 2
            end
            return band(n, 0xFFFFFFFF)
        end

        rshift = function(n, bits)
            local high_bit = 0
            if n < 0 then
                -- negative
                n = bnot(math.abs(n)) + 1
                high_bit = 0x80000000
            end
            local floor = math.floor
            for i = 1, bits do
                n = n / 2
                n = bor(floor(n), high_bit)
            end
            return floor(n)
        end
    end
end
if not tohex then
    tohex = function(a) return string.sub(string.format('%08x', a), -8) end
end
if not rol then
    rol = function(a, b) return bor(lshift(a, b), rshift(a, 32-b)) end
end
if not bswap then
    bswap = function(a)
        return bor(rshift(a, 24), band(rshift(a, 8), 0xff00), lshift(band(a, 0xff00), 8), lshift(a, 24))
    end
end

local function tr_f(a, b, c, d, x, s) return rol(bxor(d, band(b, bxor(c, d))) + a + x, s) + b end
local function tr_g(a, b, c, d, x, s) return rol(bxor(c, band(d, bxor(b, c))) + a + x, s) + b end
local function tr_h(a, b, c, d, x, s) return rol(bxor(b, c, d) + a + x, s) + b end
local function tr_i(a, b, c, d, x, s) return rol(bxor(c, bor(b, bnot(d))) + a + x, s) + b end

local function transform(x, a1, b1, c1, d1)
    local a, b, c, d = a1, b1, c1, d1

    a = tr_f(a, b, c, d, x[1] + 0xd76aa478, 7)
    d = tr_f(d, a, b, c, x[2] + 0xe8c7b756, 12)
    c = tr_f(c, d, a, b, x[3] + 0x242070db, 17)
    b = tr_f(b, c, d, a, x[4] + 0xc1bdceee, 22)
    a = tr_f(a, b, c, d, x[5] + 0xf57c0faf, 7)
    d = tr_f(d, a, b, c, x[6] + 0x4787c62a, 12)
    c = tr_f(c, d, a, b, x[7] + 0xa8304613, 17)
    b = tr_f(b, c, d, a, x[8] + 0xfd469501, 22)
    a = tr_f(a, b, c, d, x[9] + 0x698098d8, 7)
    d = tr_f(d, a, b, c, x[10] + 0x8b44f7af, 12)
    c = tr_f(c, d, a, b, x[11] + 0xffff5bb1, 17)
    b = tr_f(b, c, d, a, x[12] + 0x895cd7be, 22)
    a = tr_f(a, b, c, d, x[13] + 0x6b901122, 7)
    d = tr_f(d, a, b, c, x[14] + 0xfd987193, 12)
    c = tr_f(c, d, a, b, x[15] + 0xa679438e, 17)
    b = tr_f(b, c, d, a, x[16] + 0x49b40821, 22)

    a = tr_g(a, b, c, d, x[2] + 0xf61e2562, 5)
    d = tr_g(d, a, b, c, x[7] + 0xc040b340, 9)
    c = tr_g(c, d, a, b, x[12] + 0x265e5a51, 14)
    b = tr_g(b, c, d, a, x[1] + 0xe9b6c7aa, 20)
    a = tr_g(a, b, c, d, x[6] + 0xd62f105d, 5)
    d = tr_g(d, a, b, c, x[11] + 0x02441453, 9)
    c = tr_g(c, d, a, b, x[16] + 0xd8a1e681, 14)
    b = tr_g(b, c, d, a, x[5] + 0xe7d3fbc8, 20)
    a = tr_g(a, b, c, d, x[10] + 0x21e1cde6, 5)
    d = tr_g(d, a, b, c, x[15] + 0xc33707d6, 9)
    c = tr_g(c, d, a, b, x[4] + 0xf4d50d87, 14)
    b = tr_g(b, c, d, a, x[9] + 0x455a14ed, 20)
    a = tr_g(a, b, c, d, x[14] + 0xa9e3e905, 5)
    d = tr_g(d, a, b, c, x[3] + 0xfcefa3f8, 9)
    c = tr_g(c, d, a, b, x[8] + 0x676f02d9, 14)
    b = tr_g(b, c, d, a, x[13] + 0x8d2a4c8a, 20)

    a = tr_h(a, b, c, d, x[6] + 0xfffa3942, 4)
    d = tr_h(d, a, b, c, x[9] + 0x8771f681, 11)
    c = tr_h(c, d, a, b, x[12] + 0x6d9d6122, 16)
    b = tr_h(b, c, d, a, x[15] + 0xfde5380c, 23)
    a = tr_h(a, b, c, d, x[2] + 0xa4beea44, 4)
    d = tr_h(d, a, b, c, x[5] + 0x4bdecfa9, 11)
    c = tr_h(c, d, a, b, x[8] + 0xf6bb4b60, 16)
    b = tr_h(b, c, d, a, x[11] + 0xbebfbc70, 23)
    a = tr_h(a, b, c, d, x[14] + 0x289b7ec6, 4)
    d = tr_h(d, a, b, c, x[1] + 0xeaa127fa, 11)
    c = tr_h(c, d, a, b, x[4] + 0xd4ef3085, 16)
    b = tr_h(b, c, d, a, x[7] + 0x04881d05, 23)
    a = tr_h(a, b, c, d, x[10] + 0xd9d4d039, 4)
    d = tr_h(d, a, b, c, x[13] + 0xe6db99e5, 11)
    c = tr_h(c, d, a, b, x[16] + 0x1fa27cf8, 16)
    b = tr_h(b, c, d, a, x[3] + 0xc4ac5665, 23)

    a = tr_i(a, b, c, d, x[1] + 0xf4292244, 6)
    d = tr_i(d, a, b, c, x[8] + 0x432aff97, 10)
    c = tr_i(c, d, a, b, x[15] + 0xab9423a7, 15)
    b = tr_i(b, c, d, a, x[6] + 0xfc93a039, 21)
    a = tr_i(a, b, c, d, x[13] + 0x655b59c3, 6)
    d = tr_i(d, a, b, c, x[4] + 0x8f0ccc92, 10)
    c = tr_i(c, d, a, b, x[11] + 0xffeff47d, 15)
    b = tr_i(b, c, d, a, x[2] + 0x85845dd1, 21)
    a = tr_i(a, b, c, d, x[9] + 0x6fa87e4f, 6)
    d = tr_i(d, a, b, c, x[16] + 0xfe2ce6e0, 10)
    c = tr_i(c, d, a, b, x[7] + 0xa3014314, 15)
    b = tr_i(b, c, d, a, x[14] + 0x4e0811a1, 21)
    a = tr_i(a, b, c, d, x[5] + 0xf7537e82, 6)
    d = tr_i(d, a, b, c, x[12] + 0xbd3af235, 10)
    c = tr_i(c, d, a, b, x[3] + 0x2ad7d2bb, 15)
    b = tr_i(b, c, d, a, x[10] + 0xeb86d391, 21)

    return tobit(a + a1), tobit(b + b1), tobit(c + c1), tobit(d + d1)
end

local function md5_update(self, s)
    local m, len = s, #s
    if len % 4 ~= 0 then
        m = m .. '\128' .. rep('\0', 63 - band(len + 8, 63)) ..
                char(band(lshift(len, 3), 255), band(rshift(len, 5), 255), band(rshift(len, 13), 255),
            band(rshift(len, 21), 255)) .. '\0\0\0\0'
    end
    local a, b, c, d = self.a, self.b, self.c, self.d
    local x, k = self.x, self.k
    for i = 1, #m, 4 do
        local m0, m1, m2, m3 = byte(m, i, i + 3)
        x[k] = bor(m0, lshift(m1, 8), lshift(m2, 16), lshift(m3, 24))
        if k == 16 then
            a, b, c, d = transform(x, a, b, c, d)
            k = 1
        else
            k = k + 1
        end
    end
    self.a, self.b, self.c, self.d, self.k = a, b, c, d, k
    self.len = self.len + len
    return self
end

local function md5_finish(self)
    local len = self.len
    if len % 4 == 0 then
        local s = '\128' .. rep('\0', 63 - band(len + 8, 63)) ..
                  char(band(lshift(len, 3), 255), band(rshift(len, 5), 255), band(rshift(len, 13), 255),
                band(rshift(len, 21), 255)) .. '\0\0\0\0'
        md5_update(self, s)
    end
    return tohex(bswap(self.a)) .. tohex(bswap(self.b)) .. tohex(bswap(self.c)) .. tohex(bswap(self.d))
end

local md5 = {}

function md5.new()
    return {
        a = 0x67452301,
        b = 0xefcdab89,
        c = 0x98badcfe,
        d = 0x10325476,
        x = {},
        k = 1,
        len = 0,
        update = md5_update,
        finish = md5_finish,
    }
end

function md5.sum(s)
    return md5.new():update(s):finish()
end

return md5