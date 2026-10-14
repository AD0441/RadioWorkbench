#ifndef AUDIO_RING_H
#define AUDIO_RING_H
#include <stdint.h>
#include <stddef.h>
typedef struct RadioRing RadioRing;
RadioRing *radio_ring_create(size_t capacity);
void radio_ring_destroy(RadioRing *ring);
// One producer, one consumer. Capacity is fixed. Overflow drops entire blocks.
size_t radio_ring_write(RadioRing *ring, const float * const *channels, size_t channel_count, size_t count);
size_t radio_ring_write_mono(RadioRing *ring, const float *left, const float *right, size_t count);
size_t radio_ring_read(RadioRing *ring, float *output, size_t maximum);
uint64_t radio_ring_dropped(RadioRing *ring);
uint64_t radio_ring_written(RadioRing *ring);
#endif
