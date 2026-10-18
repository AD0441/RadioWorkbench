// RadioWorkbench compatibility layer for the standalone GPL-3.0-or-later ALE decoder.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <cmath>
#include <algorithm>
using u1_t = uint8_t;
using u2_t = uint16_t;
using u4_t = uint32_t;
using s2_t = int16_t;
#define ARRAY_LEN(a) (int(sizeof(a) / sizeof((a)[0])))
#define bf(v, hi, lo) ((uint32_t(v) >> (lo)) & ((uint32_t(1) << ((hi)-(lo)+1))-1))
#define b13(v) bf(v,13,13)
#define b15(v) bf(v,15,15)
#define b20(v) bf(v,20,20)
#define RED ""
#define GREEN ""
#define YELLOW ""
#define CYAN ""
#define MAGENTA ""
#define NORM ""
#define kiwi_snprintf_buf(b, ...) snprintf(b, sizeof(b), __VA_ARGS__)
#define kiwi_snprintf_ptr(b, n, ...) snprintf(b, n, __VA_ARGS__)
extern "C" void radio_ale_emit(const char *text);
inline void radio_ale_append(char *dest, size_t capacity, const char *src) {
    const size_t used = strnlen(dest, capacity);
    if (used < capacity - 1) strncat(dest, src, capacity - used - 1);
}
inline void radio_ale_text_message(char *dest, size_t capacity, const char *kind, const char *text) {
    size_t length = strnlen(text, 256);
    while (length && (text[length-1] == ' ' || text[length-1] == '\r' || text[length-1] == '\n')) --length;
    length = std::min(length, capacity > 12 ? capacity - 12 : size_t(0));
    snprintf(dest, capacity, "%s: \"%.*s\"", kind, int(length), text);
}
