# Copyright (c) 2023 Molodos
# The ElegooNeptuneThumbnails plugin is released under the terms of the AGPLv3 or higher.


from array import array
from PIL import ImageColor

def parse_thumbnail(img, width, height, default_background) -> str:
    img.thumbnail((width, height))
    pixels = img.load()
    result = ""
    img_size = img.size
    color16 = array('H')
    default_background = ImageColor.getcolor(default_background if default_background.startswith('#') else "#" + default_background, "RGB")
    try:
        for i in range(img.size[0]): # for every pixel:
            for j in range(img.size[1]):
                pixel_color = pixels[j, i]
                if pixel_color[3] < 255:
                    alpha = pixel_color[3] / 255
                    pixel_color = (int(pixel_color[0] * alpha + (1 - alpha) * default_background[0]),
                                   int(pixel_color[1] * alpha + (1 - alpha) * default_background[1]),
                                   int(pixel_color[2] * alpha + (1 - alpha) * default_background[2]))
                r = pixel_color[0] >> 3
                g = pixel_color[1] >> 2
                b = pixel_color[2] >> 3
                rgb = (r << 11) | (g << 5) | b
                color16.append(rgb)
        output_data = bytearray(img_size[0] * img_size[1] * 10)
        ColPic_EncodeStr(color16, img_size[0], img_size[1], output_data,
                                                    img_size[0] * img_size[1] * 10, 1024)

        j = 0
        for i in range(len(output_data)):
            if output_data[i] != 0:
                result += chr(output_data[i])
                j += 1

    except Exception as e:
        raise e

    return result

def ColPic_EncodeStr(fromcolor16, picw, pich, outputdata: bytearray, outputmaxtsize, colorsmax):
    qty = 0
    temp = 0
    strindex = 0
    hexindex = 0
    TempBytes = bytearray(4)
    qty = ColPicEncode(fromcolor16, picw, pich, outputdata, outputmaxtsize, colorsmax)
    if qty == 0:
        return 0
    temp = 3 - qty % 3
    while temp > 0 and qty < outputmaxtsize:
        outputdata[qty] = 0
        qty += 1
        temp -= 1

    if qty * 4 / 3 >= outputmaxtsize:
        return 0
    hexindex = qty
    strindex = qty * 4 / 3
    while hexindex > 0:
        hexindex -= 3
        strindex -= 4
        TempBytes[0] = outputdata[hexindex] >> 2
        TempBytes[1] = outputdata[hexindex] & 3
        TempBytes[1] <<= 4
        TempBytes[1] += outputdata[hexindex + 1] >> 4
        TempBytes[2] = outputdata[hexindex + 1] & 15
        TempBytes[2] <<= 2
        TempBytes[2] += outputdata[hexindex + 2] >> 6
        TempBytes[3] = outputdata[hexindex + 2] & 63
        TempBytes[0] += 48
        if chr(TempBytes[0]) == '\\':
            TempBytes[0] = 126
        TempBytes[1] += 48
        if chr(TempBytes[1]) == '\\':
            TempBytes[1] = 126
        TempBytes[2] += 48
        if chr(TempBytes[2]) == '\\':
            TempBytes[2] = 126
        TempBytes[3] += 48
        if chr(TempBytes[3]) == '\\':
            TempBytes[3] = 126
        outputdata[int(strindex)] = TempBytes[0]
        outputdata[int(strindex) + 1] = TempBytes[1]
        outputdata[int(strindex) + 2] = TempBytes[2]
        outputdata[int(strindex) + 3] = TempBytes[3]

    qty = qty * 4 / 3
    outputdata[int(qty)] = 0
    return qty


def ColPicEncode(fromcolor16, picw, pich, outputdata: bytearray, outputmaxtsize, colorsmax):
    l0 = U16HEAD()
    Head0 = ColPicHead3()
    Listu16 = []
    for i in range(1024):
        Listu16.append(U16HEAD())

    ListQty = 0
    enqty = 0
    dotsqty = picw * pich
    if colorsmax > 1024:
        colorsmax = 1024
    for i in range(dotsqty):
        ListQty = ADList0(fromcolor16[i], Listu16, ListQty, 1024)

    for index in range(1, ListQty):
        l0 = Listu16[index]
        for i in range(index):
            if l0.qty >= Listu16[i].qty:
                aListu16 = bListu16 = Listu16.copy()
                for j in range(index - i):
                    Listu16[i + j + 1] = aListu16[i + j]

                Listu16[i] = l0
                break

    while ListQty > colorsmax:
        l0 = Listu16[ListQty - 1]
        minval = 255
        fid = -1
        for i in range(colorsmax):
            cha0 = Listu16[i].A0 - l0.A0
            if cha0 < 0:
                cha0 = 0 - cha0
            cha1 = Listu16[i].A1 - l0.A1
            if cha1 < 0:
                cha1 = 0 - cha1
            cha2 = Listu16[i].A2 - l0.A2
            if cha2 < 0:
                cha2 = 0 - cha2
            chall = cha0 + cha1 + cha2
            if chall < minval:
                minval = chall
                fid = i

        for i in range(dotsqty):
            if fromcolor16[i] == l0.colo16:
                fromcolor16[i] = Listu16[fid].colo16

        ListQty = ListQty - 1

    for n in range(len(outputdata)):
        outputdata[n] = 0

    Head0.encodever = 3
    Head0.oncelistqty = 0
    Head0.mark = 98419516
    Head0.ListDataSize = ListQty * 2
    outputdata[0] = 3
    outputdata[12] = 60
    outputdata[13] = 195
    outputdata[14] = 221
    outputdata[15] = 5
    outputdata[16] = ListQty * 2 & 255
    outputdata[17] = (ListQty * 2 & 65280) >> 8
    outputdata[18] = (ListQty * 2 & 16711680) >> 16
    outputdata[19] = (ListQty * 2 & 4278190080) >> 24
    sizeofColPicHead3 = 32
    for i in range(ListQty):
        outputdata[sizeofColPicHead3 + i * 2 + 1] = (Listu16[i].colo16 & 65280) >> 8
        outputdata[sizeofColPicHead3 + i * 2 + 0] = Listu16[i].colo16 & 255

    enqty = Byte8bitEncode(fromcolor16, sizeofColPicHead3, Head0.ListDataSize >> 1, dotsqty, outputdata,
                           sizeofColPicHead3 + Head0.ListDataSize,
                           outputmaxtsize - sizeofColPicHead3 - Head0.ListDataSize)
    Head0.ColorDataSize = enqty
    Head0.PicW = picw
    Head0.PicH = pich
    outputdata[4] = picw & 255
    outputdata[5] = (picw & 65280) >> 8
    outputdata[6] = (picw & 16711680) >> 16
    outputdata[7] = (picw & 4278190080) >> 24
    outputdata[8] = pich & 255
    outputdata[9] = (pich & 65280) >> 8
    outputdata[10] = (pich & 16711680) >> 16
    outputdata[11] = (pich & 4278190080) >> 24
    outputdata[20] = enqty & 255
    outputdata[21] = (enqty & 65280) >> 8
    outputdata[22] = (enqty & 16711680) >> 16
    outputdata[23] = (enqty & 4278190080) >> 24
    return sizeofColPicHead3 + Head0.ListDataSize + Head0.ColorDataSize


def ADList0(val, Listu16, ListQty, maxqty):
    qty = ListQty
    if qty >= maxqty:
        return ListQty
    for i in range(qty):
        if Listu16[i].colo16 == val:
            Listu16[i].qty += 1
            return ListQty

    A0 = val >> 11 & 31
    A1 = (val & 2016) >> 5
    A2 = val & 31
    Listu16[qty].colo16 = val
    Listu16[qty].A0 = A0
    Listu16[qty].A1 = A1
    Listu16[qty].A2 = A2
    Listu16[qty].qty = 1
    ListQty = qty + 1
    return ListQty


def Byte8bitEncode(fromcolor16, listu16Index, listqty, dotsqty, outputdata: bytearray, outputdataIndex, decMaxBytesize):
    listu16 = outputdata
    dots = 0
    srcindex = 0
    decindex = 0
    lastid = 0
    temp = 0
    while dotsqty > 0:
        dots = 1
        for i in range(dotsqty - 1):
            if fromcolor16[srcindex + i] != fromcolor16[srcindex + i + 1]:
                break
            dots += 1
            if dots == 255:
                break

        temp = 0
        for i in range(listqty):
            aa = listu16[i * 2 + 1 + listu16Index] << 8
            aa |= listu16[i * 2 + 0 + listu16Index]
            if aa == fromcolor16[srcindex]:
                temp = i
                break

        tid = int(temp % 32)
        if tid > 255:
            tid = 255
        sid = int(temp / 32)
        if sid > 255:
            sid = 255
        if lastid != sid:
            if decindex >= decMaxBytesize:
                dotsqty = 0
                break
            outputdata[decindex + outputdataIndex] = 7
            outputdata[decindex + outputdataIndex] <<= 5
            outputdata[decindex + outputdataIndex] += sid
            decindex += 1
            lastid = sid
        if dots <= 6:
            if decindex >= decMaxBytesize:
                dotsqty = 0
                break
            aa = dots
            if aa > 255:
                aa = 255
            outputdata[decindex + outputdataIndex] = aa
            outputdata[decindex + outputdataIndex] <<= 5
            outputdata[decindex + outputdataIndex] += tid
            decindex += 1
        else:
            if decindex >= decMaxBytesize:
                dotsqty = 0
                break
            outputdata[decindex + outputdataIndex] = 0
            outputdata[decindex + outputdataIndex] += tid
            decindex += 1
            if decindex >= decMaxBytesize:
                dotsqty = 0
                break
            aa = dots
            if aa > 255:
                aa = 255
            outputdata[decindex + outputdataIndex] = aa
            decindex += 1
        srcindex += dots
        dotsqty -= dots

    return decindex


class U16HEAD:

    def __init__(self):
        self.colo16 = 0
        self.A0 = 0
        self.A1 = 0
        self.A2 = 0
        self.res0 = 0
        self.res1 = 0
        self.qty = 0


class ColPicHead3:

    def __init__(self):
        self.encodever = 0
        self.res0 = 0
        self.oncelistqty = 0
        self.PicW = 0
        self.PicH = 0
        self.mark = 0
        self.ListDataSize = 0
        self.ColorDataSize = 0
        self.res1 = 0
        self.res2 = 0