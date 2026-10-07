/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifndef NEGATIVEOFFSET_H
#define NEGATIVEOFFSET_H

#include <cstdint>

namespace NegativeOffset
{
inline bool hasNegativeDisplacement(const int x, const int y)
{
    return x < 0 || y < 0;
}

inline bool usesNegativeDisplacement(const bool outfitNegative, const bool mountNegative)
{
    return outfitNegative || mountNegative;
}

inline bool useGroundFirstPass(const bool mapDrawGroundFirst, const bool negativeOffsets)
{
    return mapDrawGroundFirst || negativeOffsets;
}

inline bool isFlatGround(const bool ground, const int width, const int height, const bool displaced)
{
    return ground && width == 1 && height == 1 && !displaced;
}

template <typename Stream>
int32_t readDisplacement(Stream& stream, const bool signedOffsets)
{
    return signedOffsets ? stream.get16() : stream.getU16();
}
}

#endif
