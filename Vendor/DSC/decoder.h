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

// RadioWorkbench experimental adaptation: Qt containers replaced by standard C++.
#pragma once
#include <array>
#include <vector>
#include <cmath>
#include <cstddef>
class DSCDecoder {

public:

    typedef std::array<float, 10> SoftBits; //!< Soft decisions in transmission order, positive for binary 1 (B-state)

    void init(int offset);
    bool decodeBits(int bits);
    bool decodeSoftBits(const SoftBits& soft);
    bool isPhasing() const { return m_state == PHASING; }
    std::vector<signed char> getMessage() const;
    int getErrors() const { return m_errors; }

    static int m_maxBytes;

private:

    static const int BUFFER_SIZE = 3;
    signed char m_buf[3];
    SoftBits m_softBuf[3];
    SoftBits m_soft;             //!< Soft decisions for the symbol being decoded
    std::vector<float> m_margins;    //!< Soft-decision margin of each symbol in m_bytes
    static const float m_weakMargin;
    enum State {
        PHASING,
        FILL_DX,
        FILL_RX,
        DX,
        RX,
        DX_EOS,
        RX_EOS,
        DONE,
        NO_EOS
    } m_state;
    int m_idx;
    int m_errors;
    int m_phaseIdx;
    bool m_eos;
    static const signed char m_expectedSymbols[];

    std::vector<signed char> m_bytes;          //!< Soft-decision symbols, with weak symbols erased (-1)
    std::vector<signed char> m_hardBytes;      //!< Symbols from a copy without detectable errors, else -1

    bool decodeSymbol(signed char symbol);
    void eraseWeakSymbols();
    static signed char bitsToSymbol(unsigned int bits);
    static unsigned char reverse(unsigned char b);
    signed char selectSymbol(signed char dx, signed char rx, const SoftBits& dxSoft, const SoftBits& rxSoft);
    static float symbolMetric(int symbol, const SoftBits& soft);
    static int bestSymbol(const SoftBits& soft, float& bestMetric, float& nextMetric);

};


