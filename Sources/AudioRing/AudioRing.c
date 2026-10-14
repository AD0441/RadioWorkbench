#include "AudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>
struct RadioRing {
    float *samples;
    size_t capacity;
    _Atomic size_t write_index, read_index;
    _Atomic uint64_t dropped;
};
RadioRing *radio_ring_create(size_t capacity) {
    if (!capacity || capacity > 16777216) return NULL;
    RadioRing *ring = calloc(1, sizeof(*ring));
    if (!ring) return NULL;
    ring->samples = calloc(capacity, sizeof(float));
    if (!ring->samples) { free(ring); return NULL; }
    ring->capacity = capacity;
    atomic_init(&ring->write_index, 0); atomic_init(&ring->read_index, 0); atomic_init(&ring->dropped, 0);
    return ring;
}
void radio_ring_destroy(RadioRing *ring) { if (ring) { free(ring->samples); free(ring); } }
size_t radio_ring_write(RadioRing *ring, const float * const *channels, size_t channel_count, size_t count) {
    if (!ring || !channels || !channel_count) return 0;
    for (size_t channel = 0; channel < channel_count; ++channel) if (!channels[channel]) return 0;
    size_t write = atomic_load_explicit(&ring->write_index, memory_order_relaxed);
    size_t read = atomic_load_explicit(&ring->read_index, memory_order_acquire);
    if (count > ring->capacity - (write - read)) {
        atomic_fetch_add_explicit(&ring->dropped, count, memory_order_relaxed); return 0;
    }
    for (size_t i = 0; i < count; ++i) {
        float value = 0;
        for (size_t channel = 0; channel < channel_count; ++channel) value += channels[channel][i];
        ring->samples[(write + i) % ring->capacity] = value / channel_count;
    }
    atomic_store_explicit(&ring->write_index, write + count, memory_order_release);
    return count;
}
size_t radio_ring_read(RadioRing *ring, float *output, size_t maximum) {
    if (!ring || !output) return 0;
    size_t read = atomic_load_explicit(&ring->read_index, memory_order_relaxed);
    size_t write = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    size_t count = write - read;
    if (count > maximum) count = maximum;
    for (size_t i = 0; i < count; ++i) output[i] = ring->samples[(read + i) % ring->capacity];
    atomic_store_explicit(&ring->read_index, read + count, memory_order_release);
    return count;
}
size_t radio_ring_write_mono(RadioRing *ring, const float *left, const float *right, size_t count) {
    const float *channels[2] = { left, right };
    return radio_ring_write(ring, channels, right ? 2 : 1, count);
}
uint64_t radio_ring_dropped(RadioRing *ring) { return atomic_load_explicit(&ring->dropped, memory_order_relaxed); }
uint64_t radio_ring_written(RadioRing *ring) { return atomic_load_explicit(&ring->write_index, memory_order_acquire); }
