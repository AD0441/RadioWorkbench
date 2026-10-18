///////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2023 Jon Beniston, M7RCE <jon@beniston.com>                     //
//                                                                               //
// This program is free software; you can redistribute it and/or modify          //
// it under the terms of the GNU General Public License as published by          //
// the Free Software Foundation as version 3 of the License, or                  //
// (at your option) any later version.                                           //
//                                                                               //
// This program is distributed in the hope that it will be useful,               //
// but WITHOUT ANY WARRANTY; without even the implied warranty of                //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the                  //
// GNU General Public License V3 for more details.                               //
//                                                                               //
// You should have received a copy of the GNU General Public License             //
// along with this program. If not, see <http://www.gnu.org/licenses/>.          //
///////////////////////////////////////////////////////////////////////////////////

// RadioWorkbench experimental adaptation: standard containers; bounded frame/ECC validator.
#include "decoder.h"
#include <algorithm>

bool frameValid(const std::vector<signed char>& v) {
    if (v.size() < 18 || v.size() >= 40 || v[0] != v[1]) return false;
    if (v[0]!=102 && v[0]!=112 && v[0]!=114 && v[0]!=116 && v[0]!=120 && v[0]!=123) return false;
    if (v[0]!=112) {
        int category=v[v[0]==116?2:7];
        if(category!=100 && category!=108 && category!=110 && category!=112) return false;
    }
    size_t self=v[0]==112?2:(v[0]==116?3:8);
    if(self+5>=v.size()) return false;
    for(size_t i=self;i<self+5;i++) if(v[i]<0 || v[i]>99)return false;
    if (v[v.size()-2]!=117 && v[v.size()-2]!=122 && v[v.size()-2]!=127) return false;
    unsigned char ecc=0;
    for (size_t i=1;i+1<v.size();++i) { if(v[i]<0) return false; ecc ^= v[i]; }
    return v.back()>=0 && ecc==v.back();
}

// Doesn't include 125 111 125 as these will have be detected already, in DSDDemodSink
const signed char DSCDecoder::m_expectedSymbols[] = {
    110,
    125, 109,
    125, 108,
    125, 107,
    125, 106
};

int DSCDecoder::m_maxBytes = 40; // Max bytes in any message

// A symbol whose soft-decision metric beats the next best symbol by less than
// this fraction of its total soft-decision magnitude is considered weak.
const float DSCDecoder::m_weakMargin = 0.1f;

void DSCDecoder::init(int offset)
{
    if (offset == 0)
    {
        m_state = FILL_DX;
    }
    else
    {
        m_phaseIdx = offset;
        m_state = PHASING;
    }
    m_idx = 0;
    m_errors = 0;
    m_bytes = std::vector<signed char>();
    m_hardBytes = std::vector<signed char>();
    m_margins.clear();
    m_eos = false;
}

bool DSCDecoder::decodeSymbol(signed char symbol)
{
    bool ret = false;

    switch (m_state)
    {
    case PHASING:
        // Check if received phasing signals are as expected
        if (symbol != m_expectedSymbols[9-m_phaseIdx]) {
            m_errors++;
        }
        m_phaseIdx--;
        if (m_phaseIdx == 0) {
            m_state = FILL_DX;
        }
        break;

    case FILL_DX:
        // Fill up buffer
        m_softBuf[m_idx] = m_soft;
        m_buf[m_idx++] = symbol;
        if (m_idx == BUFFER_SIZE)
        {
            m_state = RX;
            m_idx = 0;
        }
        else
        {
            m_state = FILL_RX;
        }
        break;

    case FILL_RX:
        // RX symbols 105 and 104 fill the two time-diversity slots after
        // the six DX phasing characters and before the first repeats.
        if (   ((m_idx == 1) && (symbol != 105))
            || ((m_idx == 2) && (symbol != 104))
           )
        {
            m_errors++;
        }
        m_state = FILL_DX;
        break;

    case RX:
        {
            signed char a = selectSymbol(m_buf[m_idx], symbol, m_softBuf[m_idx], m_soft);

            if ((a == 117 || a == 122 || a == 127)) {
                m_state = DX_EOS;
            } else {
                m_state = DX;
            }

            if (m_bytes.size() > m_maxBytes)
            {
                ret = true;
                m_state = NO_EOS;
                eraseWeakSymbols();
            }
        }
        break;

    case DX:
        // Save received character in buffer
        m_softBuf[m_idx] = m_soft;
        m_buf[m_idx] = symbol;
        m_idx = (m_idx + 1) % BUFFER_SIZE;
        m_state = RX;
        break;

    case DX_EOS:
        // Save, EOS symbol
        m_softBuf[m_idx] = m_soft;
        m_buf[m_idx] = symbol;
        m_idx = (m_idx + 1) % BUFFER_SIZE;
        m_state = RX_EOS;
        break;

    case RX_EOS:
        selectSymbol(m_buf[m_idx], symbol, m_softBuf[m_idx], m_soft);
        m_state = DONE;
        ret = true;
        eraseWeakSymbols();
        break;

    case DONE:
    case NO_EOS:
        break;

    }

    return ret;
}

// Reverse order of bits in a byte
unsigned char DSCDecoder::reverse(unsigned char b)
{
   b = (b & 0xF0) >> 4 | (b & 0x0F) << 4;
   b = (b & 0xCC) >> 2 | (b & 0x33) << 2;
   b = (b & 0xAA) >> 1 | (b & 0x55) << 1;
   return b;
}

// Convert 10 bits to a symbol
// Returns -1 if error detected
signed char DSCDecoder::bitsToSymbol(unsigned int bits)
{
    signed char data = reverse(bits >> 3) >> 1;
    int zeros = 7-__builtin_popcount(data);
    int expectedZeros = bits & 0x7;
    if (zeros == expectedZeros) {
        return data;
    } else {
        return -1;
    }
}

// Decode 10-bits to symbols then remove errors using repeated symbols
bool DSCDecoder::decodeBits(int bits)
{
    SoftBits soft;
    for (int i = 0; i < 10; i++) {
        soft[i] = ((bits >> (9 - i)) & 1) ? 1.0f : -1.0f;
    }
    return decodeSoftBits(soft);
}

// Decode 10 soft decisions to a symbol then remove errors using repeated symbols
bool DSCDecoder::decodeSoftBits(const SoftBits& soft)
{
    unsigned int bits = 0;
    for (int i = 0; i < 10; i++) {
        bits = (bits << 1) | (soft[i] > 0.0f ? 1 : 0);
    }
    m_soft = soft;
    return decodeSymbol(bitsToSymbol(bits));
}

        // Prefer the classic selection of a copy without detectable errors, as used before
// soft decision was added, as when that gives a valid message it is at least as
// reliable. Otherwise, use the soft decisions.
std::vector<signed char> DSCDecoder::getMessage() const
{
    if (frameValid(m_hardBytes) || !frameValid(m_bytes)) {
        return m_hardBytes;
    } else {
        return m_bytes;
    }
}

// The ECC only reliably detects a single wrong symbol. When several soft decisions
// are weak, a wrong combination of them could pass the ECC, so mark them as
// erasures (-1), which makes the message invalid.
void DSCDecoder::eraseWeakSymbols()
{
    int weak = 0;
    for (float margin : m_margins) {
        weak += margin < m_weakMargin;
    }
    if (weak > 1)
    {
        for (int i = 0; i < m_bytes.size(); i++)
        {
            if (m_margins[i] < m_weakMargin) {
                m_bytes[i] = -1;
            }
        }
    }
}

// Correlation of soft decisions with the 10-bit codeword of a symbol:
// 7 information bits LSB first, then the number of zeros (B-states) MSB first.
float DSCDecoder::symbolMetric(int symbol, const SoftBits& soft)
{
    const int zeros = 7 - __builtin_popcount((unsigned char) symbol);
    float metric = 0.0f;
    for (int i = 0; i < 7; i++) {
        metric += ((symbol >> i) & 1) ? soft[i] : -soft[i];
    }
    for (int i = 0; i < 3; i++) {
        metric += ((zeros >> (2 - i)) & 1) ? soft[7 + i] : -soft[7 + i];
    }
    return metric;
}

// Symbol whose codeword best matches the soft decisions, and the metrics of
// the best and next best symbols
int DSCDecoder::bestSymbol(const SoftBits& soft, float& bestMetric, float& nextMetric)
{
    int best = 0;
    bestMetric = -1e30f;
    nextMetric = -1e30f;
    for (int symbol = 0; symbol < 128; symbol++)
    {
        float metric = symbolMetric(symbol, soft);
        if (metric > bestMetric)
        {
            nextMetric = bestMetric;
            bestMetric = metric;
            best = symbol;
        }
        else if (metric > nextMetric)
        {
            nextMetric = metric;
        }
    }
    return best;
}

// Select time diversity symbol. The classic selection uses a copy without
// detectable errors. The soft selection combines both copies and chooses the
// symbol that best matches them, unless both copies agree without errors.
signed char DSCDecoder::selectSymbol(signed char dx, signed char rx, const SoftBits& dxSoft, const SoftBits& rxSoft)
{
    signed char s;
    if (dx != -1)
    {
        s = dx;  // First received character has no detectable error
        if (dx != rx) {
            m_errors++;
        }
    }
    else if (rx != -1)
    {
        s = rx;  // Second received character has no detectable error
        m_errors++;
    }
    else
    {
        s = -1; // Both received characters have errors
        m_errors += 2;
    }
    m_hardBytes.push_back(s);

    SoftBits combined;
    float scale = 0.0f;
    for (int i = 0; i < 10; i++)
    {
        combined[i] = dxSoft[i] + rxSoft[i];
        scale += std::fabs(combined[i]);
    }
    float bestMetric, nextMetric;
    const int best = bestSymbol(combined, bestMetric, nextMetric);
    if ((dx == -1) || (dx != rx)) {
        s = best;
    }
    float margin;
    if (scale <= 0.0f) {
        margin = 0.0f;
    } else if (s == best) {
        margin = (bestMetric - nextMetric) / scale;
    } else {
        margin = (symbolMetric(s, combined) - bestMetric) / scale;
    }

    m_bytes.push_back(s);
    m_margins.push_back(margin);

    return s;
}
