// MINTIA scope - simple PC oscilloscope based upon kit_scope -
//   v0.73p1 by @pado3 on Feb 9, 2021
//
//    Original: Kyutech Arduino Scope Prototype  v0.73
//    (C) 2012-2019 M.Kurata Kyushu Institute of Technology
//    # excluding "class FFT".
//    https://www.iizuka.kyutech.ac.jp/faculty/physicalcomputing/pc_kitscope
//
//   history:
//     Feb  9, 2021  v0.73p1 for MINTIA scope from v0.73
//                   # change default value of gain & offset
//                   # append offset CAL
//                   # modify over-range treatment
//                   # set default capture folder to Downloads
//                   # make original skin
//                   # larger font, show release name, change print color
//     Apr 10, 2019  v0.73  for recent macOS
//     Mar 20, 2016  v0.72  just ver# was changed.
//     Oct  5, 2015  v0.70  to fit Processing-3.0
//                   # runs on Processing2 or 3.
//                   # no more runs on Processing1
//
//                   dc/ac coupling support (board = 2 or 3)
//                   # additional circuit is required
//                   # to take advantage of ac coupling
//
//                   screen capture support
//                   # available when 'stopped'
//
//     Nov 25, 2014  v0.60  dks2014 board support
//
//     Feb 22, 2013  v0.52  to fit Processing-2.0b7
//
//     Oct 29, 2012  v0.51  bugfix
//                   MouseButton didn't work with Processing-2.0b.
//                   Trigger level display wasn't sometimes updated.
//
//     Mar 20, 2012  v0.50  1st release

String relname = "v0.72p1";

int board = 0;
// 0: default
// 1: dks2014 board
// 2: selectable  dc/ac coupling
// 3: selectable  dc/ac coupling (with settings UI)

// default values
// modified for MINTIA scope
final int def_ch1coup    =    0; // 0:dc 1:ac
final int def_ch1gain_dc =  250; // gain 0.25 = 1000/4
final int def_ch1gain_ac =  250;
final int def_ch1bias_dc =  219; // DC offset = (1000/1024)*(0-(-8.941))/4
final int def_ch1bias_ac =  250;
final int def_ch2coup    =    0;
final int def_ch2bias_ac =  250;
final int def_ch2gain_dc =  250;
final int def_ch2gain_ac =  250;
// final int def_ch2bias_dc =  219;  // same as def_ch1biasdc on MINTIA scope
// original
// final int def_ch1coup    =    0; // 0:dc 1:ac
// final int def_ch1gain_dc = 1000; // 1.0=1000 0.5=500 x2.0=2000 (100..20000)
// final int def_ch1gain_ac = 1000; // 1.0=1000 0.5=500 x2.0=2000 (100..20000)
// final int def_ch1bias_dc =    0; // A1 port voltage that is regarded as 0V (0..500)
// final int def_ch1bias_ac =  250; // A1 port voltage that is regarded as 0V (0..500)
// final int def_ch2coup    =    0;
// final int def_ch2gain_dc = 1000;
// final int def_ch2gain_ac = 1000;
// final int def_ch2bias_dc =    0; // A2 port voltage that is regarded as 0V (0..500)
// final int def_ch2bias_ac =  250; // A2 port voltage that is regarded as 0V (0..500)

final boolean dumpcrcerr = false;

// although this value should be around 1.135 according to the ATmega328
// datasheet, it seems 1.083 is practical in reality.
final float bandgapvolt  = 1.083; // volt

int         setcfgflg    = 0;     // bit0:bandgap bit1:opt-osc
int         bootstep;
int         fgendipsw    = -2;
int         exitreq      = 0;

int         tgt_tlvl;

import java.util.*;
import java.io.*;
import processing.serial.*;


void
setup()
{
    // setup() moved here!
    // It seems Processing3 can't find 'size()' unless the line
    // is near the top of this source file.
    size(1200, 640);
    frameRate(15);
    setup2();
}


class OscConfigOne {
    final int    speed;
    final int    equiv;
    final int    realnum;
    final int    tokanum;
    final int    rate;      // ksps
    final int    ratereal;  // ksps

    OscConfigOne(int i0,int i1,int i2,int i3,int i4,int i5) {
        speed    = i0;
        equiv    = i1;
        realnum  = i2;
        tokanum  = i3;
        rate     = i4;
        ratereal = i5;
    }
};

final OscConfigOne osccfg[] = {
  new OscConfigOne(0, 0,  1000,    1,  50, 50),
  new OscConfigOne(1, 0,  1000,    1,  20, 20),
  new OscConfigOne(2, 0,  1000,    1,  10, 10),
  new OscConfigOne(3, 0,  1000,    1,   5,  5),

  new OscConfigOne(4, 1,    52,   20,1000, 50),
  new OscConfigOne(5, 1,   104,   10, 500, 50),
  new OscConfigOne(6, 1,   260,    4, 200, 50),
  new OscConfigOne(7, 1,   520,    2, 100, 50),

  new OscConfigOne(8, 2,   200,    1,   2,  2),
};


class HorizonCfg {
    final int    usdiv;
    final int    idxequv;
    final int    idxreal;
    HorizonCfg(int i0,int i1,int i2) {
        usdiv   = i0;
        idxequv = i1;
        idxreal = i2;
    }
};

final HorizonCfg   hzncfg[] = {
  new HorizonCfg(     1, 4,  0),  //  0   1usec/div
  new HorizonCfg(     2, 4,  0),  //  1   2usec/div
  new HorizonCfg(     5, 4,  0),  //  2   5usec/div
  new HorizonCfg(    10, 4,  0),  //  3  10usec/div
  new HorizonCfg(    20, 4,  0),  //  4  20usec/div
  new HorizonCfg(    50, 4,  0),  //  5  50usec/div
  new HorizonCfg(   100, 4,  0),  //  6 100usec/div
  new HorizonCfg(   200, 5,  0),  //  7 200usec/div
  new HorizonCfg(   500, 6,  0),  //  8 500usec/div
  new HorizonCfg(  1000, 7,  0),  //  9   1msec/div
  new HorizonCfg(  2000, 0,  0),  // 10   2msec/div
  new HorizonCfg(  5000, 1,  1),  // 11   5msec/div
  new HorizonCfg( 10000, 2,  2),  // 12  10msec/div
  new HorizonCfg( 20000, 3,  3),  // 13  20msec/div
  new HorizonCfg( 50000, 8,  8),  // 14  50msec/div
  new HorizonCfg(100000, 8,  8),  // 15 100msec/div
  new HorizonCfg(200000, 8,  8),  // 16 200msec/div
  new HorizonCfg(500000, 8,  8),  // 17 500msec/div
};


class ColorCfg {
    final color  bk;  // grid back
    final color  grd; // grid color
    final color  c01; // general 
    final color  c02; // dispinfo
    final color  c03; // for mag
    final color  c04; // for measure
    final color  ch1;
    final color  ch2;
    final color  ch1f;
    final color  ch2f;
    final int    stw01; // stroke weight 
    final int    stw02; // stroke weight for grid
    ColorCfg(color wbk, color wgrd,
             color wc01, color wc02, color wc03 , color wc04,
             color wch1, color wch2, color wch1f, color wch2f,
             int   wstw01, int wstw02) {
        bk   = wbk;
        grd  = wgrd;
        c01  = wc01;
        c02  = wc02;
        c03  = wc03;
        c04  = wc04;
        ch1  = wch1;
        ch2  = wch2;
        ch1f = wch1f;
        ch2f = wch2f;
        stw01 = wstw01;
        stw02 = wstw02;
    }
};


final ColorCfg  colset_d = new ColorCfg( // for display
    color(  0,   0,   0), // grid back
    color(  0,   0, 200), // grid color
    color(255, 255, 255), // general
    color(200, 200, 200), // dispinfo
    color(  0, 255,   0), // for mag
    color(180, 180, 180), // for measure
    color(250, 100, 250), // ch1
    color(250, 250,   0), // ch2
    color(250, 100, 250), // ch1f
//    color(  0,   0, 200), // ch2f
    color(250, 250,   0), // ch2f for MINTIA scope
    1,
    1
);

final ColorCfg  colset_p = new ColorCfg( // for printing, MINTIA scope
    color(255, 255, 255), // grid back, white
    color(  0,   0,   0), // grid color, black
    color(  0,   0,   0), // general
    color(  0,   0,   0), // dispinfo
    color(  0,   0,   0), // for mag
    color(  0,   0,   0), // for measure
    color(255,   0,   0), // ch1, red
    color(  0,   0, 255), // ch2, blue
    color(255,   0,   0), // ch1f
    color(  0,   0, 255), // ch2f 
    3,
    2
);
/*
final ColorCfg  colset_p = new ColorCfg( // for printing, original
    color(181, 181, 181), // grid back
    color(  0,   0, 200), // grid color
    color(  0,   0,   0), // general
    color(  0,   0,   0), // dispinfo
    color(  0,   0,   0), // for mag
    color(  0,   0,   0), // for measure
    color(250, 100, 250), // ch1
    color(250, 250,   0), // ch2
    color(  0,   0,   0), // ch1f
    color(  0,   0,   0), // ch2f
    3,
    2
);
*/

class Scr {
    final ByteArrayOutputStream    bs;
    final PrintStream              ps;

    float    ox, oy;
    float    wx, wy;
    int      gx, gy;

    int      mesreq;  // 0:none 1:cross 2:drag
    int      m0x, m0y, m1x, m1y;

    float    divx, divy;
    float    gx0, gy0, gx1, gy1;

    float    bai, vrf, bias, pos, var, volt2div, div2dot;

    float    fa[];

    String   fgmsg;
    ColorCfg colset;


    Scr(int igx, int igy) {
        bs = new ByteArrayOutputStream();
        ps = new PrintStream(bs);

        fa = new float[1024];

        fgmsg = null;

        gx   = igx;
        gy   = igy;
        divx = igx;
        divy = igy;

        wy = 400;
        wx = wy * divx / divy;
        ox = 50 + 58;
        oy = wy / divy + 79;

        gx0 = ox;
        gx1 = ox + wx;
        gy0 = oy;
        gy1 = oy + wy;
        colset = colset_d;
    }

    private void setcalc(int ch) {

        vrf = (float)pm_vref.valnum() / 500.0;
        div2dot = wy / divy;

        if ((ch & 1) == 0) {
           if (pm_ch1coup.valnum() != 0) {
               bai = 1000.0 / (float)pm_ch1gainac.valnum();
               bias = (float)pm_ch1biasac.valnum() / 100.0;
           }
           else {
               bai = 1000.0 / (float)pm_ch1gaindc.valnum();
               bias = (float)pm_ch1biasdc.valnum() / 100.0;
           }
        }
        else {
           if (pm_ch2coup.valnum() != 0) {
               bai = 1000.0 / (float)pm_ch2gainac.valnum();
               bias = (float)pm_ch2biasac.valnum() / 100.0;
           }
           else {
               bai = 1000.0 / (float)pm_ch2gaindc.valnum();
               // modified for MINTIA scope, DC offset of ch2 is same as ch1
               // bias = (float)pm_ch2biasdc.valnum() / 100.0;
               bias = (float)pm_ch1biasdc.valnum() / 100.0;
           }
        }

        if (ch == 0) {
           pos = pm_ch1ofs.valnum() / 100.0 + 5.0;
           var = pm_ch1var.valnum() / 1000.0;
           volt2div = (float)pm_ch1div.valnum() / 1000.0;
        }
        else if (ch == 1) {
           pos = pm_ch2ofs.valnum() / 100.0 + 5.0;
           var = pm_ch2var.valnum() / 1000.0;
           volt2div = (float)pm_ch2div.valnum() / 1000.0;
        }
        else {  // for fft
           pos  = pm_fftofs.valnum() / 100.0 + 5.0;
           var  = pm_fftvar.valnum() / 1000.0;
           volt2div = (float)pm_fftdiv.valnum() / 1000.0;
        }
    }

    private float sv2volt(int sv) {
        return  ((float)sv / 51.0 - bias) * bai * vrf;
    }

    private float volt2div(float volt) {
        return  volt * volt2div;
    }

    private float div2dot(float div) {
        return  gy1 - pos * div2dot - div * div2dot * var;
    }

    private float dot2volt(float dot) {
        return  (gy1 - dot - pos * div2dot) / ( volt2div * div2dot * var);
    }

    private float dot2volt(int dot) {   return  dot2volt((float)dot);    }
    private float sv2div(int sv) {      return  volt2div(sv2volt(sv));  }
    private float sv2dot(int sv) {      return  div2dot(sv2div(sv));    }
    private float volt2dot(float volt) {return  div2dot(volt2div(volt));}

    void fgenmsg(String s) {
        fgmsg = s;
    }

    void
    colset(boolean paper)
    {
        colset = (paper) ? colset_p : colset_d;
    }

    void
    colchg()
    {
        colset = (colset == colset_p) ? colset_d : colset_p;
    }

    void
    grid() {
        int    i, j;
        float  x, y;


        pushStyle();
        strokeWeight(0);
        fill(colset.bk);
        rect(56, 77, 520, 520); // fill gridback
        stroke(colset.grd);
        strokeWeight(colset.stw02);
        for(i = 0; i <= gx; i++) {
            x = wx * float(i) / float(gx) + ox;
            line(int(x), int(gy0), int(x), int(gy1));
        }
        for(j = 0; j <= gy; j++) {
            y = wy * float(j) / float(gy) + oy;
            line(int(gx0), int(y), int(gx1), int(y));
        }
        popStyle();
    }

    private void
    clippedline_sub(boolean noxclip, boolean dots,
                    float x0, float y0, float x1, float y1) {
        float    cx0, cy0, cx1, cy1, alpha;
        int      ix0, iy0, ix1, iy1;
        boolean  inf;
        
        float wgy0 = gy0 -35; // wave grid limitter (high side) for MINTIA scope
        float wgy1 = gy1 +25; // wave grid limitter (low side) for MINTIA scope

        if (x0 > x1) {
            alpha = x1;
            x1 = x0;
            x0 = alpha;
            alpha = y1;
            y1 = y0;
            y0 = alpha;
        }
        cx0 = x0;
        cx1 = x1;
        cy0 = y0;
        cy1 = y1;

        inf = (cx1 - cx0 < 0.1) ? true : false;  // treatment too little dx
        alpha = (inf) ? 0 : (y1 - y0) / (x1 - x0);

        if (! noxclip) {  // clip x before/after grid
            if (cx1 <= gx0 || cx0 >= gx1)
                return;
            if (! inf) {
                if (cx0 < gx0) {
                    cy0 = alpha * (gx0 - x0) + y0;
                    cx0 = gx0;
                }
                if (gx1 < cx1) {
                    cy1 = alpha * (gx1 - x0) + y0;
                    cx1 = gx1;
                }
            }
        }
        // display limitter is modified for MINTIA scope
        if (cy0 <= cy1) {  // down wave
            // if (cy1 < wgy0 || cy0 > wgy1)  // originally, when over the grid area
            //     return;                    // do not draw a wave
            if (cy0 < wgy0) cy0 = wgy0;  // I feel better to stay at a limitter
            if (cy1 < wgy0) cy1 = wgy0;
            if (wgy1 < cy0) cy0 = wgy1;
            if (wgy1 < cy1) cy1 = wgy1;
            
            if (cy0 < wgy0) {
                if (! inf)
                    cx0 = (wgy0 - y0) / alpha + x0;
                cy0 = wgy0;
            }
            if (cy1 > wgy1) {
                if (! inf)
                    cx1 = (wgy1 - y0) / alpha + x0;
                cy1 = wgy1;
            }
        }
        else {  // up wave, also set limitter
            // if (cy0 < wgy0 || cy1 > wgy1)
            //     return;
            if (cy0 < wgy0) cy0 = wgy0;  // stay at a limitter
            if (cy1 < wgy0) cy1 = wgy0;
            if (wgy1 < cy0) cy0 = wgy1;
            if (wgy1 < cy1) cy1 = wgy1;
            
            if (cy0 > wgy1) {
                if (! inf)
                    cx0 = (wgy1 - y0) / alpha + x0;
                cy0 = wgy1;
            }
            if (cy1 < wgy0) {
                if (! inf)
                    cx1 = (wgy0 - y0) / alpha + x0;
                cy1 = wgy0;
            }
        }
/*
        // original limitter code before MINTIA scope
        if (cy0 <= cy1) {
            if (cy1 < gy0 || cy0 > gy1)
                return;
            
            if (cy0 < gy0) {
                if (! inf)
                    cx0 = (gy0 - y0) / alpha + x0;
                cy0 = gy0;
            }
            if (cy1 > gy1) {
                if (! inf)
                    cx1 = (gy1 - y0) / alpha + x0;
                cy1 = gy1;
            }
        }
        else {
            if (cy0 < gy0 || cy1 > gy1)
                return;
            
            if (cy0 > gy1) {
                if (! inf)
                    cx0 = (gy1 - y0) / alpha + x0;
                cy0 = gy1;
            }
            if (cy1 < gy0) {
                if (! inf)
                    cx1 = (gy0 - y0) / alpha + x0;
                cy1 = gy0;
            }
        }
*/
        ix0 = (int)(cx0 + 0.5);
        ix1 = (int)(cx1 + 0.5);
        iy0 = (int)(cy0 + 0.5);
        iy1 = (int)(cy1 + 0.5);

        line(ix0, iy0, ix1, iy1);
        if (dots) {
            pushStyle();
            noStroke();
            if (cx0 == x0 && cy0 == y0)
                rect(ix0, iy0, 3, 3);
            if (cx1 == x1 && cy1 == y1)
                rect(ix1, iy1, 3, 3);
            popStyle();
        }
    }

    void  clippedline(boolean dots, float x0, float y0, float x1, float y1) {
        clippedline_sub(false, dots, x0, y0, x1, y1);
    }

    void  clippedline_nox(float x0, float y0, float x1, float y1) {
        clippedline_sub(true, false, x0, y0, x1, y1);
    }


    private String sigfig3(float val, String u0, String u1, String u2) {
        String    ret, fmt;
        int       c;

        c = (val < 0.0) ? '-' : ' ';
        val = abs(val);

        if (u0 != null && (val >= 1000000.0 || u1 == null)) {
            val /= 1000000.0;
        }
        else if (u1 != null && (val >= 1000.0 || u2 == null)) {
            val /= 1000.0;
            u0 = u1;
        }
        else {
            u0 = u2;
        }

        if (val >= 100.0)
            fmt = " %c%3.0f%s";
        else if (val >= 10.0)
            fmt = "%c%4.1f%s";
        else
            fmt = "%c%4.2f%s";

        ps.printf(fmt, c, val, u0);
        ret = bs.toString();
        bs.reset();
        return  ret;
    }
    private String sigfig3e6(float val, String u0, String u1, String u2) {
        return  sigfig3(val * 1e+6f, u0, u1, u2);
    }


    void measure_req(int mreq, int im0x, int im0y, int im1x, int im1y) {
        mesreq = mreq;
        m0x = im0x;
        m0y = im0y;
        m1x = im1x;
        m1y = im1y;
    }

    void dispmeasure(Smp smp) {
        int       x, y, i, tx, ty, tx0, ty0;
        float     us, v0, v1;
        String    s, smv;

        if (mesreq == 0)
            return;

        x = m1x;
        y = m1y;
        if (x > gx1)
            x = int(gx1);
        else if (x < gx0)
            x = int(gx0);
        if (y > gy1)
            y = int(gy1);
        else if (y < gy0)
            y = int(gy0);

        if (mesreq == 1) {
            int    fft;


            fft = pm_fftver.valnum();
            tx0 = (int)gx0;
            ty0 = (int)gy1 + 25;

            textAlign(LEFT, TOP);

            if (fft >= 0) {
                float  fc;

                ty0  = (int)gy1 + 48;

                tx = tx0 + 220;

                setcalc(2 + pm_fftsig.valnum());
                v1 = dot2volt(y);
                if ((fft & 1) != 0) {
                    smv = sigfig3e6(v1, "dBV", null, null);
                }
                else {
                    smv = (pm_fftdiv.valnum() >= 10000) ? "mv" : null;
                    smv = sigfig3e6(v1, "v", smv, null);
                }

                fc = (float)(x - (ox + wx / 2)) * divx / wx;
                fc /= pm_hmag.valnum();
                fc += 5.0 - (float)pm_hofs.valnum() / 100.0;
                fc = fc * smp.sps / (2.0 * divx);
                s = sigfig3(fc, null, "khz", "hz");

                ps.printf("FFT: %-7s %-7s", s, smv);
                text(bs.toString(), tx, ty0);
                bs.reset();
            }

            for(i = 0; i < 2; i++) {
                boolean  inv, div_mv;

                if (i == 0) {
                    tx = tx0;
                    ty = ty0;
                    setcalc(0);
                    fill(colset.ch1);
                    inv = (pm_ch1inv.valnum() != 0);
                    div_mv = (pm_ch1div.valnum() >= 10000);
                }
                else {
                    tx = tx0 + 110;
                    ty = ty0;
                    setcalc(1);
                    fill(colset.ch2);
                    inv = (pm_ch2inv.valnum() != 0);
                    div_mv = (pm_ch2div.valnum() >= 10000);
                }
                if (inv) {
                    ps.printf("CH%1d: inv", i + 1);
                }
                else {
                    v1 = dot2volt(y  ) * 1e+6f;
                    smv = (div_mv) ? "mv" : null;

                    s = sigfig3(v1, "v", smv, null);
                    ps.printf("CH%1d: %-7s", i + 1, s);
                }
                text(bs.toString(), tx, ty);
                bs.reset();
            }
            return;
        }

        us = (float)hzncfg[pm_hdiv.valnum()].usdiv;
        us *= (float)abs(x - m0x) * divx / (wx * (float)pm_hmag.valnum());

        pushStyle();
        noFill();
        stroke(colset.c04);
        strokeWeight(colset.stw02);
        rectMode(CORNERS);
        rect(m0x, m0y, x, y);
        fill(255);

        textAlign(LEFT, TOP);

        tx0 = (int)gx0;
        ty0 = (int)gy1 + 25;

        tx = tx0;
        ty = ty0;
        s = sigfig3(us, "s", "ms", "us");
        ps.printf("time: %s", s);
        text(bs.toString(), tx, ty0);
        bs.reset();
        tx += 90;

        us = (us < 0.01) ? 0.0 : 1000000.0 / us;
        s = sigfig3(us, "mhz", "khz", "hz");
        ps.printf("(%s)", s);
        text(bs.toString(), tx, ty);
        bs.reset();

        for(i = 0; i < 2; i++) {
            boolean  inv, div_mv;

            if (i == 0) {
                tx = tx0;
                ty = ty0 + 12;
                setcalc(0);
                fill(colset.ch1);
                inv = (pm_ch1inv.valnum() != 0);
                div_mv = (pm_ch1div.valnum() >= 10000);
            }
            else {
                tx = tx0;
                ty = ty0 + 24;
                setcalc(1);
                fill(colset.ch2);
                inv = (pm_ch2inv.valnum() != 0);
                div_mv = (pm_ch2div.valnum() >= 10000);
            }

            if (inv) {
                ps.printf("CH%1d: not available due to being inverted", 
                          i + 1);
                text(bs.toString(), tx, ty);
                bs.reset();
            }
            else {
                v0 = dot2volt(m0y) * 1e+6f;
                v1 = dot2volt(y  ) * 1e+6f;
                smv = (div_mv) ? "mv" : null;

                s = sigfig3(v0, "v", smv, null);
                ps.printf("CH%1d: %-7s", i + 1, s);
                text(bs.toString(), tx, ty);
                bs.reset();
                tx += 88;

                s = sigfig3(v1,"v", smv, null);
                ps.printf("> %-7s", s);
                text(bs.toString(), tx, ty);
                bs.reset();
                tx += 78;

                s = sigfig3(v1 - v0, "v", smv, null);
                ps.printf("diff: %-7s", s);
                text(bs.toString(), tx, ty);
                bs.reset();
                tx += 88;

                s = sigfig3((v0 + v1) / 2.0, "v", smv, null);
                ps.printf("mean: %-7s", s);
                text(bs.toString(), tx, ty);
                bs.reset();
            }

        
        }
        popStyle();
    }


    void dispinfo(Smp smp) {
        String         s, s2;
        int            x, xc, y, i, sps, mag;
        color          txc;
        boolean        inv, uncal;

        sps = smp.sps;
        mag = pm_hmag.valnum();

        xc = (int)(gx0 + wx / 2.0);
        pushStyle();

        fill(colset.c02);
        if (smp.ifscan()) {
            s = "scan  freerun";
        }
        else if (smp.equv != 0) {
            s = "equiv triggered";
        }
        else {
            s = (smp.trigauto != 0) ? "real  freerun" : "real  triggered";
        }
        textAlign(LEFT, TOP);
        text(s, gx0, gy0 - 20);


        y = (int)gy1 + 1;
        textAlign(LEFT, TOP);
        text(pm_hdiv.valstr(),  gx0,  y);

        s = sigfig3(sps, null, "ksps", "sps");
        textAlign(RIGHT, TOP);
        text(s, gx1, y);

        if (mag != 1) {
            ps.printf("x%dmag", mag);
            fill(colset.c03);
            textAlign(LEFT, TOP);
            text(bs.toString(), xc + 40, y);
            bs.reset();
        }


        x = int(gx1) - 100;
        y = int(gy0) -  33;
        rectMode(CORNER);
        textAlign(LEFT, TOP);
        for(i = 0; i < 2; i++) {
            if (i == 0) {
                fill(colset.ch1);
                uncal = (pm_ch1var.valnum() != 1000);
                inv   = (pm_ch1inv.valnum() != 0);
                s = "CH1 " + pm_ch1div.valstr();
            }
            else {
                fill(colset.ch2);
                uncal = (pm_ch2var.valnum() != 1000);
                inv   = (pm_ch2inv.valnum() != 0);
                s = "CH2 " + pm_ch2div.valstr();
            }
            s2 = (inv) ? "inv  " : "";
            if (uncal)
                s2 += "uncal";

            if (pm_mode.valnum() != (1 - i)) {
                noStroke();
                rect(x - 10, y + 4, 7, 7);
                stroke(255);
            }
            fill(colset.c02);
            text(s,  x, y);
            text(s2, int(gx1), y);
            y += 13;
        }


        if (pm_fftver.valnum() >= 0) {  // fft is on
            float  fc, fd;
            int    hpos;

            fill(colset.c01);
            stroke(colset.c01);

            fc = (float)sps / 4.0;                  // center freq
            fd = (float)sps / (2.0 * divx);         // freq / div

            s = sigfig3(fd, null, "khz/div", "hz/div");
            textAlign(LEFT, TOP);
            text(s, gx0 + 80, gy1 + 1.0);

            if (mesreq != 2) {
                hpos = pm_hofs.valnum();
                fc -= (fd * hpos) / 100.0;  // adjust h-position
                fd = fd * 5.0 / mag;

                y = (int)gy1 + 28;
                i = 20;

                if (fc >= 0.0) {
                    s = sigfig3(fc, null, "khz", "hz");
                    line(xc, y, xc, y - 4);
                    line(xc - i, y, xc + i, y);
                    textAlign(CENTER, TOP);
                    text(s, xc, y);
                }

                if (hpos == 0 && mag == 1) {
                    if (fc - fd >= 0.0) {
                        s = sigfig3(fc - fd, null, "khz", "hz");
                        line(gx0, y, gx0 + i + i, y);
                        line(gx0, y, gx0, y - 4);
                        textAlign(LEFT, TOP);
                        text(s, gx0, y);
                    }

                    if (fc + fd >= 0.0) {
                        s = sigfig3(fc + fd, null, "khz", "hz");
                        line(gx1, y, gx1, y - 4);
                        line(gx1 - i - i, y, gx1, y);
                        textAlign(RIGHT, TOP);
                        text(s, gx1, y);
                    }
                }
            }
        }

        switch(smphold.status()) {
        default:
        case  0:
            stroke(255);
            fill(0, 255, 0);
            txc = color(0);
            s = "running";
            break;
        case  1:
            stroke(255);
            fill(255, 255, 0);
            txc = color(0);
            s = "waiting";
            break;
        case  2:
            stroke(255);
            fill(255,   0, 0);
            txc = color(255);
            s = "stopped";
            break;
        case  3:
            stroke(255);
            fill(255, 255, 0);
            txc = color(0);
            s = "too slow signals for equivalent-time-sampling";
            break;
        }
        rectMode(CENTER);
        noStroke();
        i = (int)(textWidth(s) + 6);
        rect(xc,    gy0 - 15, i, 19);
        noFill();
        stroke(255);
        rect(xc -1, gy0 - 16, i, 19);
        textAlign(CENTER);
        fill(txc);
        text(s, xc, gy0 - 15, i, 19);

        if (fgmsg != null && mesreq == 0) {
            y = (int)gy1 + ((pm_fftver.valnum() >= 0) ? 48 : 25);
            fill(255);
            textAlign(LEFT, TOP);
            text(fgmsg, gx0, y);
        }

        popStyle();
    }


    void dispchgauge(int ch) {
        float  x, y, dv, d0v, d000, d255;
        int    i;

        pushStyle();
        strokeWeight(colset.stw01);
        switch(ch) {
        default:
        case  0: 
            setcalc(0);
            stroke(colset.ch1);
            fill(colset.ch1f);
            x = gx1 + 5;
            break;
        case  1:
            setcalc(1);
            stroke(colset.ch2);
            fill(colset.ch2f);
            x = gx1 + 20;
            break;
        case  2:
        case  3:
            setcalc(ch);
            stroke(255);
            fill(colset.c01);
            x = gx1 + 35;
        }

        if (ch < 2 && pm_tsrc.valnum() == ch) {
            String    s;
            int       tlvl;

            tlvl = pm_tlvl.valnum();
            y   = sv2dot(tlvl);
            d0v = sv2volt(tlvl);
            clippedline_nox(gx0 - 5, y, gx0, y);
            fill(colset.c01);
            if (y >= gy0 && y <= gy1) {
                s = ((pm_tslpe.valnum() == 0) ? "trig /" : "trig \\");
                textAlign(RIGHT, CENTER);
                text(s, gx0 - 8, y - 2);

                tlvl = (ch==0) ? pm_ch1div.valnum() : pm_ch2div.valnum();
                d000 = abs(d0v);
                if (d000 >= 10.0)
                    ps.printf("%4.1fv", d0v);
                else if (d000 >= 1.0)
                    ps.printf("%4.2fv", d0v);
                else if (d000 >= 0.1 || tlvl < 10000)
                    ps.printf("%4.2fv", d0v);
                else
                    ps.printf("%4.1fmv", d0v * 1000.0);
                s = bs.toString();
                bs.reset();
                textAlign(RIGHT, CENTER);
                text(s, gx0 - 8, y + 12);
            }
        }

        textAlign(LEFT, CENTER);

        d0v  = volt2div(0.0);  // y coordinate of 0.0V
        d000 = sv2div(0);      // y coordinate of ADC zero
        d255 = sv2div(255);    // y coordinate of ADC full (why 255?)

        if (ch >= 2) {  // correction for fft
            i = pm_fftver.valnum();
            if (i == 1 || i == 3) {  // dB
                d255 = volt2div( 40);  //  40dB
                d000 = volt2div(-60);  // -60dB
            }
            else {
                if (d255 - d0v < d0v - d000)
                    d255 = d0v + d0v - d000;
                d000 = d0v;
            }
        }

        clippedline_nox(x, div2dot(d000), x, div2dot(d255));
        y = div2dot(d000);
        if (gy0 <= y && y <= gy1 && abs(d000 - d0v) >= 0.01)
            clippedline_nox(x, y, x + 1, y);
        y = div2dot(d255);
        if (gy0 <= y && y <= gy1 && abs(d255 - d0v) >= 0.01)
            clippedline_nox(x, y, x + 1, y);

        y = div2dot(d0v);  // show '0' on right side of gauge
        if (y >= gy0-10 && y <= gy1+10)  // add margin for MINTIA scope
            text(0, x + 5, y - 2);

        stroke(colset.c01);
        y = div2dot(d0v);
        if (gy0 <= y && y <= gy1)
            clippedline_nox(x, y, x + 4, y);

        for(dv = 1.0; dv <= d255; dv += 1.0) {
            y = div2dot(dv);
            if (y < gy0)
                break;                
            clippedline_nox(x, y, x + 2, y);
        }
        for(dv = -1.0; dv >= d000; dv -= 1.0) {
            y = div2dot(dv);
            if (y > gy1)
                break;                
            clippedline_nox(x, y, x + 2, y);
        }

        popStyle();
    }


    void
    dispsig(Smp smp) {
        int        i, j, v, num, idx;
        float      x0, y0, x1, y1, xadd, xofs, magX;
        boolean    dual, dots, inv, wipe, seg;

        pushStyle();
        strokeWeight(colset.stw01);
        rectMode(CENTER);

        dots = (pm_dispdots.valnum() != 0);
        dual = (smp.mode == 2);
        wipe = (smp.ifscan() && pm_hscan.valnum() != 0);

        if (smp.ifscan() || (! dual)) {
            num = 1000;
            v = smp.sps;
        }
        else {
            num = 500;
            v = smp.sps * 2;
        }

        xadd = (float)pm_hmag.valnum();
        magX = 100000000.0 / ((float)v * hzncfg[pm_hdiv.valnum()].usdiv);
        xofs = ((float)pm_hofs.valnum() * xadd) / (divx * 100.0);
        xofs -= (xadd - 1.0) * magX / 2.0;
        magX *= (xadd * wx / num);
        xofs = xofs * wx + ox;
        
        for(j = 0; j < 2; j++) {
            dispchgauge(j);
            if ((! dual) && smp.mode != j)
                continue;

            idx = smp.oscval(j, ((wipe) ? -2 : -1));
            switch(j) {
            default:
            case  0: 
                setcalc(0);
                inv   = (pm_ch1inv.valnum() != 0);
                xadd  = 0.0;
                stroke(colset.ch1);
                break;
            case  1:
                setcalc(1);
                inv   = (pm_ch2inv.valnum() != 0);
                if (smp.ifscan())
                    xadd = 50.0;  // 50us
                else if (dual && smp.equv == 0)
                    xadd = 20.0;  // 20us
                else
                    xadd = 0.0;
                xadd =  (xadd * smp.sps) / 1000000.0;
                stroke(colset.ch2);
                break;
            }

            x0 = y0 = x1 = y1 = 0.0;
            seg = false;
            rectMode(CENTER);
            for(i = 0; i < num; i++) {  // draw signal wave
                if (i == idx)
                    seg = false;
                v = smp.oscval(j, i);
                if (v < 0) {
                    seg = false;
                    continue;
                }
                if (inv)
                    v = 255 - v;
                y1 = sv2dot(v);
                x1 = xofs + magX * (float(i) + xadd);
                if (seg)
                    clippedline(dots, x0, y0, x1, y1);
                x0 = x1;
                y0 = y1;
                seg = true;
            }
            if (wipe) {  // if no-roll, x-magnification treatment
                x1 = xofs + magX * (float(idx) + xadd);
                if (gx0 <= x1 && x1 <= gx1) {
                    pushStyle();
                    if (smphold.status() == 0) {
                        stroke(255);
                        line(x1, gy0, x1, gy0 - 3);
                        line(x1, gy1, x1, gy1 + 3);
                    }
                    else {
                        stroke(200);
                        line(x1, gy0, x1, gy1);
                    }
                    popStyle();
                }
            }
        }
        // for MINTIA scope, draw limit line in black dot
        stroke(colset.bk);
        for(i = int(gx0); i < int(gx1); i+=4) {
          line(i, int(gy0)-35, i+1, int(gy0)-35);
          line(i, int(gy1)+25, i+1, int(gy1)+25);
        }
        popStyle();
    }


    void
    dispfft(Smp smp) {
        int        i, v, ffnum;
        float      x0, y0, x1, y1, xofs, hmag, magX, fv;
        boolean    dual, dots;

        if (pm_fftver.valnum() < 0)
            return;   // fft is off

        pushStyle();
        rectMode(CENTER);

        dots = (pm_dispdots.valnum() != 0);
        dual = (smp.mode == 2);

        ffnum = (smp.ifscan() || (! dual)) ? 1024 : 512;

        hmag = (float)pm_hmag.valnum();
        xofs = ((float)pm_hofs.valnum() * hmag) / (divx * 100.0);
        xofs -= (hmag - 1.0) / 2.0;
        magX = hmag * wx * 2.0 / ffnum;
        xofs = xofs * wx + ox;
        

        v = pm_fftsig.valnum();
        dispchgauge(2 + v);
        setcalc(2 + v);

        for(i = 0; i < ffnum; i++)
            fa[i] = sv2volt(smp.fftval(v, i));
        fft.fft(pm_fftwin.valnum(), ffnum, fa);

        stroke(255);
        strokeWeight(colset.stw01);
        v = pm_fftver.valnum();
        x0 = y0 = -1;
        ffnum >>= 1;
        for(i = 0; i <= ffnum; i++) {
            fv = ((v & 2) != 0) ? fa[i] / 2.0 : fa[i];
            fv = ((v & 1) != 0) ? log(fv) * 4.342945 : sqrt(fv);
            if (fv < -60.0)
                fv = -60.0;
            y1 = volt2dot(fv);
            x1 = xofs + magX * float(i);
            if (x0 >= 0)
                clippedline(dots, x0, y0, x1, y1);
            x0 = x1;
            y0 = y1;
        }
        popStyle();
    }

    int conv_tlvl(int ch) {
        int       tlvl;
        float     fv;

        tlvl = pm_tlvl.valnum();

        if (ch >= 2) {
            return  (tlvl * pm_vref.valnum() + 128) / 255;
        }
        else {
            setcalc(ch);
            fv = sv2volt(tlvl) * 100.0;
            if (fv >= 0) {
                return  int(fv + 0.5);
            }
            else {
                return -int(-fv + 0.5);
            }
            //return  int(100.0 * sv2volt(tlvl) + 0.5);
        }
    }
}


class Smp {
    int[][]   buf;
    final int blen;      // 1050
    int       mode;      // 0:CH0 1:CH1 2:DUAL
    int       speed;     // 0..3:real  4..7:equiv  8:roll
    int       trig;      // bit3  = 0:auto 1:non-auto
                         // bit2  = 0:rise 1:fall
                         // bit10 = 0:ch1  1:ch2  2:ext  3:fgen
    int       triglvl;   // 0..255
    int       trigauto;  // 0:triggered  1:freerun
    int       equv;      // 0:real(including roll) 1:equiv
    int       sps;       // sampling speed

    // for rollmode
    int       blkhzn;
    int       blknum;    //  10,  20,  40, 100  blks/10divs
    int       blksz;     // 100,  50,  25,  10  samples/blk
    int       blkpkt;    // next packet counter;
    int       blkrdy;    // num of stored blocks

    // for oscval
    final int rdmax;
    int       rdadd;
    int       rdsta;
    boolean   rdwipe;

    Smp() {
        rdmax       = 1000;
        blen        = rdmax + 50;
        this.buf    = new int[2][];
        this.buf[0] = new int[blen];
        this.buf[1] = new int[blen];
        smpvoid();
    }

    void
    smpvoid() {
        speed  = 0;
        blkhzn = -1;
    }

    void
    smpcopy(Smp from) {
        int    i, j;

        if (from == null || from.speed != 8)
            return;
        blkhzn = from.blkhzn;
        blknum = from.blknum;
        blksz  = from.blksz;
        blkpkt = from.blkpkt;
        blkrdy = from.blkrdy;
        rdsta  = from.rdsta;
        rdadd  = from.rdadd;
        rdwipe = from.rdwipe;

        i = 0;
        for(j = blksz; j < blen; i++, j++) {
            buf[0][i] = from.buf[0][j];
            buf[1][i] = from.buf[1][j];
        }
    }

    boolean ifscan() {
        return  (speed == 8);
    }

    private void
    datattr(int params[], int valequv) {

        speed    = params[2];
        mode     = params[3];
        trig     = params[4];
        trigauto = params[12];
        triglvl  = params[13];
        equv     = valequv;
        sps      = 1000 * osccfg[speed].rate;
        if (speed == 8) {
            sps = sps * blksz / 100;
        }
        else {
            blkhzn = -1;
            if (mode == 2)
                sps >>= 1;
        }
    }


    int
    oscval(int ch, int idx) {  // ch:0,1 idx:0..499 or 0..999
        if (speed != 8)
            return  (idx >= 0) ? buf[ch][idx] : ((mode == 2) ? 500 : 1000);

        // for scan mode
        if (idx == -1) {
            rdwipe = false;
            if (blkrdy >= blknum)
                rdsta = 0;
            else if (blkrdy > 0)
                rdsta = rdmax - blkrdy * blksz;
            else
                rdsta = rdmax;
            rdadd = blen - rdmax;
            return  rdsta;
        }
        else if (idx == -2) {
            rdwipe = true;
            if (blkrdy >= blknum) {
                rdsta = rdmax;
                rdadd = rdmax + rdmax - blkrdy * blksz;
                return  (rdmax == rdadd) ? rdmax : (rdmax - rdadd);
            }
            else if (blkrdy > 0) {
                rdsta = blkrdy * blksz;
                rdadd = rdmax - rdsta;
                return  rdmax - rdadd;
            }
            else {
                rdsta = 0;
                rdadd = rdmax;
                return  0;
            }
        }

        if (rdwipe) {
            if (idx < rdsta) {
                idx = idx + rdadd + (blen - rdmax);
                if (idx >= blen)
                    idx -= rdmax;
                return  buf[ch][idx];
            }
        }
        else {
            if (idx >= rdsta)
                return  buf[ch][idx + blen - rdmax];
        }
        return  -1;
    }

    int
    fftval(int ch, int idx) {  // ch:0,1 idx:0..511 or 0..1023
        if (speed == 8) {
            return  buf[ch][blen - 1024 + idx];
        }
        return  buf[ch][idx];
    }


    void
    datreg_roll_clear() {
        for(int i = 0; i < blen; i++) {
            buf[0][i] = -1;
            buf[1][i] = -1;
        }
        blkrdy = -3;
    }

    boolean
    datreg_roll(int pdat[], int ri, int hznidx) {
        int    i, j;

        if (blkhzn != hznidx) {
            switch(hznidx) {
            default: return  false;  // failed!
            case 14: blksz = 100;  blknum =  10; break;
            case 15: blksz =  50;  blknum =  20; break;
            case 16: blksz =  25;  blknum =  40; break;
            case 17: blksz =  10;  blknum = 100; break;
            }
            blkhzn = hznidx;
            blkpkt = -1;
        }
        datattr(pdat, 0);

        if (pdat[1] != blkpkt) {
            for(i = 0; i < blen; i++) {
                buf[0][i] = -1;
                buf[1][i] = -1;
            }
            blkrdy = -3;
        }
        blkpkt = pdat[1] + 1;
        if (blkpkt >= 256)
            blkpkt = 0;

        j = 200 / blksz;
        for(i = blen - blksz; i < blen; i++) {
            buf[0][i] = pdat[ri + 0];
            buf[1][i] = pdat[ri + 1];
            ri += j; 
        }

        if (++blkrdy >= (blknum << 1))
            blkrdy = blknum;
        return  true;
    }


    void
    datreg_real(int pdat[], int ri) {
        int    i, ch, idx;

        datattr(pdat, 0);
        ch = pdat[3];
        if (ch == 2) { // real & dual
            idx = 0;
            for(i = 0; i < 520; i ++) {
                buf[0][idx] = pdat[ri++];
                buf[1][idx] = pdat[ri++];
                idx++;
            }
        }
        else { // real & single
            for(i = 0; i < 1040; i++)
                buf[ch][i] = pdat[ri++];
        }
    }

    void
    datreg_equv(int pdat[], int ri) {
        int    i, j, idx, ch, rnum, toka;

        datattr(pdat, 1);
        ch   = pdat[3];
        idx  = pdat[2];    // speed
        rnum = osccfg[idx].realnum;
        toka = osccfg[idx].tokanum;
        if (ch == 2)
            toka >>= 1;
        for(j = 0; j < toka; j++) {
            if (ch != 1) {
                idx = j;
                for(i = 0; i < rnum; i++) {
                    buf[0][idx] = pdat[ri++];
                    idx += toka;
                }
            }
            if (ch != 0) {
                idx = j;
                for(i = 0; i < rnum; i++) {
                    buf[1][idx] = pdat[ri++];
                    idx += toka;
                }
            }
        }
    }
}


class Smphold {
    Smp      disp;
    Smp      ready;
    Smp      read;
    Smp      reuse;
    int      numnew;
    int      timdisp;
    int      timequv;
    int      sts;

    Smphold() {
        disp    = null;
        ready   = null;
        read    = null;
        reuse   = null;
        timdisp = timequv = -1;
        numnew  = 0;
        sts     = 1;
    }



    synchronized int status() {
        int    now;

        now = millis();
        if (sts == 0 && (now - timdisp) > 1000)
            sts = 1;
        if (sts == 1 && (now - timequv) < 2000)
            return  3;

        // 0:fresh  1:not fresh  2:stopped  3:equiv error
        return  sts;
    }

    synchronized void equv_err() {
        timequv = millis();
    }

    synchronized boolean ifstopped() {
        return  (sts == 2);
    }

    synchronized void stop() {
        sts = 2;
    }

    synchronized void resume(boolean timreset) {
        if (sts == 2) {
            if (ready != null) {
                if (reuse != null) {
                    System.out.printf("smphold resume error!\n");
                }
                reuse = ready;
                ready = null;
            }
            if (timreset) {
                sts = 0;
                timdisp = millis();
            }
            else {
                sts = 1;
            }
        }
    }

    synchronized Smp getdisp() {
        if (ready == null) {
            return  disp;
        }

        if (disp != null) {
           if (reuse != null) {
               System.out.printf("reuse error\n");
           }
           reuse = disp;
        }
        disp = ready;
        ready = null;
        return  disp;
    }

    synchronized Smp getread(boolean stopreq) {
        Smp  tmp;

        if (read != null) {
            if (sts == 2)
                return  read;

            if (stopreq) {
                if (read.ifscan()) {
                    if (read.blkrdy >= read.blknum)
                        sts = 2;
                }
                else
                    sts = 2;
            }
            if (sts != 2) {
                sts = 0;
                timdisp = millis();
            }
        }

        tmp = ready;
        ready = read;
        read  = reuse;
        reuse = null;
        if (read == null) {
            if (tmp != null) {
                read = tmp;
            }
            else {
               read = new Smp();
               numnew++;
               if (numnew > 3)
                   System.out.printf("smphold new %d\n", numnew);
            }
        }
        read.smpvoid();
        read.smpcopy(ready);
        return  read;
    }
}


Smphold smphold;
Smp smpdisp, smpread;
Scr scr0;


int  pktbuf[] = new int[1100];
byte srlbuf[] = new byte[16];

int pktidx, pktin, pktdat;

Crc8  crc0, crc1;



void
setconfig(int cfg, int bg, int dip)
{
    if ((setcfgflg & 2) == 0) {
        setcfgflg |= 2;
        fgendipsw = (dip < 4) ? dip : -1;
        if (fgendipsw < 0)
            uiman.lock(pm_fgmem, true, true);
    }
    if ((setcfgflg & 1) == 0) {
        if (bg > 0) {
            bg = (int)(bandgapvolt * 1024.0 * 100.0 / bg);
            pm_vref.setrst(bg);
            pm_vref.rstval();
            setcfgflg |= 1;
        }
    }
}


int d89old = 0;
int
d89hack()
{
    int d89;

    if (board != 1)
        return  0;

    d89 = (pktbuf[5] >> 1) & 3;
    if (d89 == d89old)
        return  0;
    //System.out.printf("cupgain new %02x\n", d89);
    d89old = d89;
    return  1;
}


long prgkey;
int  sts;

int
datrcv2(int ch)
{
    prgkey = ((prgkey & 0xffffff) << 8) | ch;

    if (pktin < 0) {
        if (prgkey == 0xaa55a55aL) {
            sts = 0;
            pktidx = 0;
            pktin  = 14;
            crc0.calc(-1);
        }
        return  0;
    }

    if (pktin > 0) {
        pktbuf[pktidx++] = ch;
        crc0.calc(ch);
        pktin--;
        return  0;
    }
    {
        int ccr = crc0.calc(-1);
        if (ch != ccr) {
            if (pktbuf[0] == 2 && (byte)(ccr + 1) == (byte)ch) {
                smphold.equv_err();
            }
            else {
                System.out.printf("  crc error at sts%d  %02x should be %02x\n",
                   sts, ch, ccr);
                if (dumpcrcerr) {
                    int    z;
                    for(z = 0; z < pktidx; z++) {
                        System.out.printf("%02x,", pktbuf[z]);
                        if ((z % 8) == 7)
                            System.out.printf("\n");
                    }
                    System.out.printf("\n");
                }
            }
            pktin = -1;
            return  0;
        }
    }

    if (sts == 0) {
        if (pktbuf[0] > 5) {
            pktin = -1;
            System.out.printf("unknown packet id %d\n", pktbuf[0]);
            return  0;
        }
        pktdat = pktidx;
        if (pktbuf[0] == 0) {  // oscinfo
            sts = 1;
            pktin = pktbuf[12];
        }
        else if (pktbuf[0] == 1) { // real
            sts = 6;
            pktin  = 200;
            if (pktbuf[12] > 0 && (pktbuf[4] & 0x20) != 0) {
                tgt_tlvl = pktbuf[13];
                sts = 0;
                pktin = -1;
            }
        }
        else if (pktbuf[0] == 2) { // equiv
            sts = 6;
            pktin  = 200;
            if (pktbuf[12] > 0) {
                if (pm_tmode.valnum() == 0)
                    smphold.equv_err();
                tgt_tlvl = pktbuf[13];
                sts = 0;
                pktin = -1;
            }
        }
        else if (pktbuf[0] == 3) {  // roll
            sts = 1;
            pktin  = 200;
        }
        else if (pktbuf[0] == 4) { //gen report
            pktdat = pktidx;
            pktin = pktbuf[12];
            sts = 1;
        }
        else if (pktbuf[0] == 5) { // shut down approved
             scibuf0.rcvack(pktbuf[1]);
             pktin = -1;
             if (exitreq == 1)
                 exitreq = 2;
        }
        return  0;
    }
    else if (sts > 0) {
        if (--sts > 0) {
            pktin = (sts > 1) ? 200 : 40;
            return  0;
        }
        if (pktbuf[0] == 0) {  // oscinfo
            int    cfg, bg, dip;

            scibuf0.rcvack(pktbuf[1]);
            if (pktbuf[pktdat + 6] != 0 && bootstep == 9)
                bootstep = 1;
            //ver = (pktbuf[pktdat + 0] << 8) + pktbuf[pktdat + 1];
            cfg = (pktbuf[pktdat + 2] << 8) + pktbuf[pktdat + 3];
            bg  = (pktbuf[pktdat + 4] << 8) + pktbuf[pktdat + 5];
            dip = pktbuf[pktdat + 7];
            setconfig(cfg, bg, dip);
        }
        else if (pktbuf[0] == 1) {  // real
            int    tm = pm_tmode.valnum();

            if (smphold.status() == 0)
                d89hack();
            if (pktbuf[12] == 0 || tm == 0) {
                smpread.datreg_real(pktbuf, pktdat);
                smpread = smphold.getread(tm == 2);
            } else {
                tgt_tlvl = pktbuf[13];
            }
        }
        else if (pktbuf[0] == 2) {  // equiv
            if (smphold.status() == 0)
                d89hack();
            smpread.datreg_equv(pktbuf, pktdat);
            smpread = smphold.getread(pm_tmode.valnum() == 2);
        }
        else if (pktbuf[0] == 3) {  // rollmode
            if (smphold.status() == 0) {
             	if (d89hack() != 0)
                    smpread.datreg_roll_clear();
            }
            if (! smphold.ifstopped()) {
                if (smpread.datreg_roll(pktbuf, pktdat, pm_hdiv.valnum()))
                    smpread = smphold.getread(pm_tmode.valnum() == 2);
            } else {
                tgt_tlvl = pktbuf[13];
            }
        }
        else if (pktbuf[0] == 4) {  // gen report
             scibuf0.rcvack(pktbuf[1]);
             genc.recv(pktbuf, pktdat);
        }
        else {
            System.out.printf("unkown datrcv packet %d\n", pktbuf[0]);
        }
        if (bootstep == 9 && pktbuf[0] < 4)
            tgt_tlvl = pktbuf[13];
        pktin = -1;
    }
    else  {
        System.out.printf("  unkown datrcv error sts%d pktidx%d\n",
             sts, pktidx);
        pktin = -1;
    }
    return  0;
}


int
datrcv(byte[] bf, int num) {
    int    i, ch;
    for(i = 0; i < num; i++) {
        ch = bf[i];
        if (ch < 0)
            ch += 256;
        datrcv2(ch);
    }
    return  0;
}


class Genparam {
    int    wav;
    int    freq;
    int    duty;
    int    amp;
    int    ofs;
    int    bch;

    Genparam() {
        genconst();
    }

    void genconst() {
        wav  = constrain(wav,  0,  2);
        freq = constrain(freq, 3, 840000);
        duty = constrain(duty, 0, 100);
        amp  = constrain(amp,  0, 500);
        ofs  = constrain(ofs, -250, 750);
        bch  = constrain(bch,  0, 500);
    }

    private int c4095to500(int v4095) {
        int    ret = abs(v4095);

        ret = (200 * ret + 810) / 1638;
        return  (v4095 >= 0) ? ret : -ret;
    }

    private int c256to100(int v256) {
        int    ret = abs(v256);

        ret = (25 * ret + 32) / 64;
        return  (v256 >= 0) ? ret : -ret;
    }

    private int c500to4095(int v500) {
        int    ret = abs(v500);

        ret = (819 * ret + 50) / 100;
        return  (v500 >= 0) ? ret : -ret;
    }

    private int c100to256(int v100) {
        int    ret = abs(v100);

        ret = (128 * ret + 25) / 50;
        return  (v100 >= 0) ? ret : -ret;
    }

    void bin2volt() {
        duty = c256to100(duty);
        amp  = c4095to500(amp);
        ofs  = c4095to500(ofs);
        bch  = c4095to500(bch);
    }

    void volt2bin() {
        duty = c100to256(duty);
        amp  = c500to4095(amp);
        ofs  = c500to4095(ofs);
        bch  = c500to4095(bch);
    }

    private void prnvolt(PrintStream ps, int v, String spre) {
        if (v < 0)
            spre = spre + '-';
        v = abs(v);
        ps.printf("%s%d.%02dv", spre, v / 100, v % 100);
    }

    String dispstr(int add, int mch) {
        String   wnm[] = {"sin", "tri", "pls"};

        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        PrintStream ps = new PrintStream(buf);
        if (mch >= 0) {
            ps.printf("M%d  ", mch);
        }
        ps.printf("%s %d.%1dhz duty%d%%", 
                  wnm[wav], freq/10, freq%10, duty);
        prnvolt(ps, amp, " amp");
        prnvolt(ps, ofs, " ofs");
        prnvolt(ps, bch, " bch");
        if (add >= 0) {
            ps.printf(" add(%5d.%1d)", add/10, add%10);
        }
        return  buf.toString();
    }
}


class Genctrl {
    Genparam  gen;
    Genparam  tmp;
    int       add;
    int       mch;
    int       dipsw;
    boolean   munlock;
    String    minfo;

    Genctrl() {
        gen = new Genparam();
        tmp = new Genparam();
        add = 10;
        mch = 0;
        munlock = false;
        minfo  = null;
        dipsw = -1;
    }

    private int myunhex(int buf[], int idx, int num) {
        char    ch[] = new char[num];
        String  s;
        int     i;

        for(i = 0; i < num; i++) {
            ch[i] = (char)buf[idx++];
        }
        s = new String(ch);
        return  unhex(s);
    }

    private void mydecode(Genparam g, int pkt[], int idx) {

        g.wav  = myunhex(pkt, idx, 2); idx += 2;
        g.freq = myunhex(pkt, idx, 6); idx += 6;
        g.duty = myunhex(pkt, idx, 4); idx += 4;
        g.amp  = myunhex(pkt, idx, 4); idx += 4;
        g.ofs  = myunhex(pkt, idx, 4); idx += 4;
        g.ofs  = (int)(short)g.ofs;
        g.bch  = myunhex(pkt, idx, 4); idx += 4;
        g.bin2volt();
        dipsw  = myunhex(pkt, idx, 2); idx += 2;
    }

    void recv(int pkt[], int idx) {

        switch(pkt[idx]) {
        case 'Z':
            mydecode(gen, pkt, idx + 1);
            break;
        case 'P':       // m0 settings
        case 'Q':       // m1 settings
        case 'R':       // m2 settings
        case 'S':       // m3 settings
            mydecode(tmp, pkt, idx + 1);
            minfo = (mch == (pkt[idx] - 'P')) ? tmp.dispstr(-1, mch) : null;
            break;
        }
    }

    void memsel(int m) {
        mch = m;
        scibuf0.funcgen('m', mch);
    }
    void memread(int m) {
        if (m >= 0 && m < 4) {
            scibuf0.funcgen('M', m);
        }
    }
    void memwrite(int m) {
        if (m >= 0 && m < 4) {
            scibuf0.funcgen('M', m + 16);
        }
    }

    String dispstr() {
        return  gen.dispstr(add, -1);
    }

    void genset(Genparam g) {
        g.genconst();
        g.volt2bin();
        scibuf0.funcgen('W', g);
    }
}

Genctrl genc = new Genctrl();


class Scibuf {
    Serial         scicom;

    LinkedList     sblist;
    int            reqid;
    int            numtry;
    int            senttyp;  // 0:shutup 1:fgenmem 2:fgen 3:oscparam

    StringBuffer   sent;
    StringBuffer[] req;


    Scibuf() {
        sblist = new LinkedList();
        req    = new StringBuffer[4];
        reqid   = 1;  // 1..255
        numtry  = 0;
        sent    = null;
        scicom  = null;
    }

    boolean isOpened() {
        return  (scicom != null);
    }

    private boolean comportchk(int os, String p) {
        switch(os) {
        case  0: // mac
          if (p.startsWith("/dev/cu"))
              return  true;
          if (p.indexOf("Bluetooth-") >= 0)
              return  true;
          if (p.indexOf("MALS") >= 0)
              return  true;
          if (p.indexOf("SOC") >= 0)
              return  true;
          if (p.indexOf("CASIOMEP-")  >= 0)
              return  true;
          return  false;

        case  1: // windows
          return  false;

        case  2: // linux
          if (p.startsWith("/dev/ttyACM"))
              return  false;
          if (p.startsWith("/dev/ttyUSB"))
              return  false;
          return  true;

        default:
          return  false;
        }
    }

    private String[] comports(String[] ports) {
        List<String>    lst;
        String          pt;
        int             os;

        os = oschk.type();

        lst = new LinkedList<String>(Arrays.asList(ports));
        for(Iterator<String> i = lst.iterator(); i.hasNext(); ) {
            pt = i.next();
            if (comportchk(os, pt))
                i.remove();
        }
        return  lst.toArray(new String[0]);
    }

    void open(PApplet me, String portname) {
        Serial      scitmp;
        String[]    ports;
        int         i, tm0, key;
        boolean     established;

        // to display the messages produced by the serial library.
        // try {new Serial(this, null, 0);} catch (Exception e) {}
        // println("");

        established = false;
        scitmp      = null;

        if (portname != null) {
            ports = new String[1];
            ports[0] = portname;
        }
        else {
            ports = comports(Serial.list());

            int num = ports.length;
            if (num <= 0) {
                println("No usable serial ports found.");
                delay(1000);
                return;
            }
            else if (num == 1) {
                System.out.printf("The serial port found is %s.\n", ports[0]);
            }
            else {
                print("Serial ports found are\n    ");
                println(join(ports, "\n    "));
            }
        }
        for(i = 0; i < ports.length; i++) {
            System.out.printf("  scanning port %-20s ..", ports[i]);
            try {
                scitmp = new Serial(me, ports[i], 230400);
            } catch (Exception e) {
                System.out.printf("may be in use: %s\n", e.toString());
                continue;
            }
            tm0 = millis();
            key = 0;
            while(millis() - tm0 < 3000) {
                int  dat = scitmp.read();
                if (dat < 0) {
                    try {
                        Thread.sleep(3);
                    } catch (InterruptedException e) {
                    }
                    continue;
                }
                key = (key << 8) + dat;
                key &= 0xffffffff;
                if (key == 0xaa55a55a) {
                    established = true;
                    break;
                }
            }
            if (established)
                break;
            scitmp.clear();
            try {
                scitmp.stop();
            } catch (Exception e) {
                System.out.printf("EXCP %s\n", e.toString());
            }
            System.out.printf(" failed.\n");
        }
        if (established) {
            System.out.printf(" found.\n");
            scicom = scitmp;
        }
        else {
            System.out.printf("No arduino responded.\n");
            delay(1000);
        }
    }

    void receive() {
        int    num;

        if (scicom == null)
            return;

        while (true) {
            num = scicom.available();
            if (num <= 0)
                break;
            num = scicom.readBytes(srlbuf);
            datrcv(srlbuf, num);
        }
    }

    private StringBuffer getsb(int typ, boolean ovrwrt) {
        StringBuffer    sb;

        sb = req[typ];
        if (ovrwrt == false && sb != null)
            return  null;          // already busy
        if (sb == null) {
            if (sent != null && senttyp == typ) {
                sb = sent;         // overwrite 'sent'
                sent = null;
            }
            else if (sblist.size() > 0)
                sb = (StringBuffer)sblist.remove();
            else
                sb = new StringBuffer(32);
        }
        sb.delete(0, sb.length());
        req[typ] = sb;
        return  sb;
    }

    private void backsb(StringBuffer bye) {
        bye.delete(0, bye.length());
        sblist.add(bye);
    }

    private char newreqid() {
        if (++reqid > 255)
            reqid = 1;
        return  (char)reqid;
    }


    void rcvack(int ackid) {
        if (sent != null && reqid == ackid) {
            backsb(sent);
            sent = null;
        }
    }


    void
    comsend() {
        int    len, i;

        if (scicom == null)
            return;

        if (sent == null) {
            for(i = 0; i < req.length; i++) {
                if (req[i] != null) {
                    sent = req[i];
                    req[i] = null;
                    senttyp = i;
                    break;
                }
            }
            if (sent == null)
                return;
            sent.setCharAt(2, newreqid());
            crcset(sent);
            numtry = 0;
        }

        len = sent.length();
        for(i = 0; i < len; i++) {
            int  tm = millis() + 5;  // wait for 5 milli seconds.
            scicom.write(sent.charAt(i));
            while((tm - millis()) > 0) {
                try {
                    Thread.sleep(1);
                } catch (InterruptedException e) {
                }
            }
        }
        if (++numtry >= 32) {
            System.out.printf("comsend retry give-up(%3d)\n", numtry);
            backsb(sent);
            sent = null;
        }
    }


    void
    dump(StringBuffer sb) {
        int    i;
        for(i = 0; i < sb.length(); i++) {
            System.out.printf("%2d [%02x]\n", i, (int)sb.charAt(i));
        }
    }


    private void
    crcset(StringBuffer sb) {
        int    i;

        while(sb.length() < 16) {
            sb.append(char(0));
        }

        crc1.calc(-1);
        for(i = 0; i < sb.length(); i++) {
            crc1.calc(sb.charAt(i));
        }
        sb.append(char(crc1.calc(-1)));
    }


    void
    oscparams(int speed, int input, 
              int trig, int treq, int tlvl, int tdly,
              int ofreq, int oduty, int cgain)  {
        StringBuffer    sb;

        sb = getsb(3, true);
        sb.append("$A?");
        sb.append(char((speed >>  0) & 255));
        sb.append(char((input >>  0) & 255));
        sb.append(char((trig  >>  0) & 255));
        sb.append(char((treq  >>  0) & 255));
        sb.append(char((tlvl  >>  0) & 255));
        sb.append(char((tdly  >>  8) & 255));
        sb.append(char((tdly  >>  0) & 255));
        sb.append(char((ofreq >> 16) & 255));
        sb.append(char((ofreq >>  8) & 255));
        sb.append(char((ofreq >>  0) & 255));
        sb.append(char((oduty >>  0) & 255));
        sb.append(char((cgain >>  0) & 255));
    }


    void
    shutup() {
        StringBuffer    sb;

        sb = getsb(0, false);
        if (sb != null)
            sb.append("$Q?");
    }


    void
    funcgen(int cmd, int arg) {
        StringBuffer    sb;

        sb = getsb(1, false);
        if (sb != null) {
            sb.append("$G?");
            sb.append(char((cmd         ) & 255));
            sb.append(char((arg         ) & 255));
        }
    }

    void
    funcgen(int cmd, Genparam g) {
        StringBuffer    sb;
        int             wk;

        sb = getsb(2, true);
        wk = g.ofs + 5000;
        sb.append("$G?");
        sb.append(char((cmd         ) & 255));
        sb.append(char((g.wav  >>  0) & 255));
        sb.append(char((g.freq >> 16) & 255));
        sb.append(char((g.freq >>  8) & 255));
        sb.append(char((g.freq >>  0) & 255));
        sb.append(char((g.duty >>  8) & 255));
        sb.append(char((g.duty >>  0) & 255));
        sb.append(char((g.amp  >>  8) & 255));
        sb.append(char((g.amp  >>  0) & 255));
        sb.append(char((wk     >>  8) & 255));
        sb.append(char((wk     >>  0) & 255));
        sb.append(char((g.bch  >>  8) & 255));
        sb.append(char((g.bch  >>  0) & 255));
    }
}

Scibuf    scibuf0 = new Scibuf();


static HashSet actions = new HashSet();
void doactions() {
    Iterator    i;
    UIaction    act;

    i = actions.iterator();
    while(i.hasNext()) {
        act = (UIaction)i.next();
        act.doaction();
    }
}


abstract class UIaction {
    int     reqflg;

    UIaction() {
        this(null, 0);
    }
    UIaction(UIparam param) {
        this(param, 0);
    }
    UIaction(UIparam param, int arg) {
        actions.add(this);
        reqflg = 0;
        if (param != null)
            param.register(this, arg);
    }
    void action(UIparam me, int arg) {
        reqflg |= arg;
    }

    protected boolean flagtest(int flag, int val) {
        return  ((flag & val) != 0);
    }

    protected int getflag() {
        int    ret;

        ret = reqflg;
        reqflg = 0;
        return  ret;
    }
    abstract void doaction();
}


abstract class UIparam {
    UIaction   acttgt;
    int        actarg;

    UIparam() {
        acttgt = null;
        actarg = 0;
    }

    void register(UIaction p, int arg) {
        acttgt = p;
        actarg = arg;
    }

    void action() {
        if (acttgt != null)
            acttgt.action(this, actarg);
    }

    int decimalinfo() {
        return  0;
    }

    boolean typeSel() {
        return  false;
    }

    void setval(StringBuffer sb) {
        return;
    }

    boolean appendchk(StringBuffer sb, char ch) {
        return  false;
    }

    String valstrraw(boolean foredit) {
        return  null;
    }

    abstract String valstr();
    abstract int    valnum();
    abstract void   chgval(boolean sft, int add);
    abstract void   rstval();
}


class UIsvpair {
    final String    s;
    final int       v;
    UIsvpair(String is, int iv) {
        s = is;
        v = iv;
    }
};


class UIparamStr extends UIparam {
    String          rst;
    String          val;

    UIparamStr() {
        this("");
    }

    UIparamStr(String ival)
    {
       rst = ival;
       val = ival;
    }

    void setrst(String newrst) {
        rst = newrst;
    }

    void rstval() {
        val = rst;
        //action();
    }

    void setval(String newval) {
        val = newval;
    }

    void setval(StringBuffer sb) {
        setval(sb.toString());
    }

    boolean appendchk(StringBuffer sb, char ch) {
        final String okch = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_";

        if (sb.length() < 16 && okch.indexOf(ch) >= 0)
            return  true;
        return  false;
    }

    void chgval(boolean sft, int add) {
    }

    String valstrraw(boolean foredit) {
        return  val;
    }

    String valstr() {
        return  val;
    }

    int valnum() {
        return  0;
    }
}


class UIparamNum extends UIparam {
    final ByteArrayOutputStream    bs = new ByteArrayOutputStream();
    final PrintStream              ps = new PrintStream(bs);
    final int       min;
    final int       max;
    final int       decimal;
    final String    nmunit;
    int             val;
    int             rst;

    UIparamNum(String inm, int ival, int imin, int imax) {
        this(inm, ival, imin, imax, ival, 0);
    }

    UIparamNum(String inm, int ival, int imin, int imax, int irst) {
        this(inm, ival, imin, imax, irst, 0);
    }

    UIparamNum(String inm, int ival, int imin, int imax, int irst, int idec)
    {
        nmunit = inm;
        val = ival;
        min = imin;
        max = imax;
        rst = irst;
        decimal = idec;
    }

    void setrst(int newrst) {
        rst = newrst;
    }

    void rstval() {
        val = rst;
        action();
    }

    private void setval_sub(int newval, boolean doact) {
        newval = constrain(newval, min, max);
        if (val != newval) {
            val = newval;
            if (doact)
                action();
        }
    }

    void setval_noact(int newval) {
        setval_sub(newval, false);
    }

    void setval(int newval) {
        setval_sub(newval, true);
    }

    void setval(StringBuffer sb) {
        float    fv;

        try {
            fv = Float.parseFloat(sb.toString());
        } catch(Exception e) {
            return;
        };
        for(int i = 0; i < decimal; i++)
            fv *= 10.0;
        setval(round(fv));
    }

    boolean appendchk(StringBuffer sb, char ch) {
        final String    okch = "0123456789.+-";
        int             len  = sb.length();

        if (len >= 8 || okch.indexOf(ch) < 0)
            return  false;
        if ((ch == '+' || ch == '-') && len > 0)
            return  false;
        if (ch == '.' && sb.indexOf(".") >= 0)
            return  false;

        return  true;
    }

    void chgval(boolean sft, int add) {
        setval(val + add);
    }

    String valstrraw(boolean foredit) {
        String    s;
        int       tmp;

        tmp = val;
        if (val < 0) {
            ps.printf("-");
            tmp = -val;
        }
        switch(decimal) {
        default:  ps.printf("%d"     , tmp               );  break;
        case  1:  ps.printf("%d.%01d", tmp/10  , tmp%10  );  break;
        case  2:  ps.printf("%d.%02d", tmp/100 , tmp%100 );  break;
        case  3:  ps.printf("%d.%03d", tmp/1000, tmp%1000);  break;
        }
        s = bs.toString();
        bs.reset();
        return  s;
    }

    String valstr() {
        String    s;

        s = valstrraw(false);
        if (nmunit != null)
            s += nmunit;
        return  s;
    }

    int valnum() {
        return  val;
    }

    int decimalinfo() {
        return  decimal;
    }
}


class UIparamSel extends UIparam {
    final UIsvpair[]  pairs;
    final boolean     loop;
    int               def;
    int               idx;

    UIparamSel(int iidx, boolean iloop, UIsvpair p[]) {
        this(iidx, iloop, p, iidx);
    }

    UIparamSel(int iidx, boolean iloop, UIsvpair p[], int idef) {
        pairs = p;
        idx   = iidx;
        loop  = iloop;
        def   = idef;
    }

    private int chkidx(int newidx) {
        if (newidx < 0 || newidx >= pairs.length)
            newidx = idx;
        return  newidx;
    }

    void setidx_noact(int newidx) {
        idx = chkidx(newidx);
    }

    void setidx(int newidx) {
        setidx_noact(newidx);
        action();
    }

    void setrst(int newrst) {
        def = chkidx(newrst);
    }

    void rstval() {
        setidx(def);
    }

    void chgval(boolean sft, int add) {
        int    nx;

        if (add == 0)
            return;
        nx = idx + ((add > 0) ? 1 : -1);
        if (nx < 0)
            nx = (loop) ? pairs.length - 1 : idx;
        else if (nx >= pairs.length)
            nx = (loop) ? 0 : idx;
        if (idx != nx) {
            idx = nx;
            action();
        }
    }

    String valstr() {
        return  pairs[idx].s;
    }

    int valnum() {
        return  pairs[idx].v;
    }

    boolean typeSel() {
        return  true;
    }
}


class UIvparts {
    final String    name;
    int             dx;
    int             dy;
    final int       tx;
    final int       brd;
    final int       grp;
    final int       attr;
    final UIparam   param;
    boolean         locked;
    int             mx0, my0, mx1, my1;

    UIvparts(int igrp, int ix, int iy, int itx, int ibrd, int iattr, String inm, UIparam iparam) {
        grp    = igrp;
        name   = inm;
        dx     = ix;
        dy     = iy;
        tx     = itx;
        brd    = ibrd;
        param  = iparam;
        locked = false;
        attr   = iattr;
        mx0    = -1;
    }
    UIvparts(int igrp, int ix, int iy, int itx, int ibrd, String inm, UIparam iparam) {
        this(igrp, ix, iy, itx, ibrd, 0, inm, iparam);
    }
}


class UIman {
    private UIvparts        pms[];
    private int             cursor;
    private boolean         focus;
    private StringBuffer    ksb;


    UIman(UIvparts ipms[]) {
        int    i, n;

        for(i = n = 0; i < ipms.length; i++) {
            if (ipms[i].brd == 0x00 || (ipms[i].brd & (1 << board)) != 0x00)
                n++;
        }
        pms = new UIvparts[n];
        for(i = n = 0; i < ipms.length; i++) {
            if (ipms[i].brd == 0x00 || (ipms[i].brd & (1 << board)) != 0x00)
                pms[n++] = ipms[i];
        }
        cursor = 0;
        focus  = false;

        ksb = new StringBuffer(24);
    }

    private void kclean() {
        ksb.delete(0, ksb.length());
    }

    private UIparam  tgtparam() {
        return  pms[cursor].param;
    }


    void
    chgval(boolean sft, int add) {
        UIparam    p;

        p = tgtparam();
        p.chgval(sft, add);
        kclean();
    }

    void
    rstval(boolean grp) {
        UIparam    p;
        int        g, i;

        kclean();
        if (grp) {
            g = abs(pms[cursor].grp);
            for(i = 0; i < pms.length; i++) {
                if (g == abs(pms[i].grp))
                    pms[i].param.rstval();
            }
        }
        else {
          p = tgtparam();
          p.rstval();
        }
    }

    int
    decimalinfo() {
        UIparam    p;

        p = tgtparam();
        return  p.decimalinfo();
    }

    boolean
    focus() {
        return  focus;
    }

    private void curset(int itgt) {
        if (pms[itgt].locked == false && cursor != itgt) {
            cursor = itgt;
            kclean();
            focus = false;
        }
    }

    void
    curmov(boolean sft, int add) {
        int    g, nx;

        g = pms[cursor].grp;
        nx = cursor;
        while(true) {
            if (add > 0) {
                if (++nx >= pms.length)
                    nx = 0;
            }
            else if (add < 0) {
                if (nx == 0)
                    nx = pms.length;
                nx--;
            }
            if (pms[nx].grp == 0 || pms[nx].locked)
                continue;

            if (sft == false || (pms[nx].grp > 0 && -g != pms[nx].grp))
                break;
            if (nx == cursor)
                sft = false;
        }
        curset(nx);
    }


    void lock(UIparam pa, boolean lck) {
        lock(pa, lck, false);
    }

    void
    lock(UIparam pa, boolean lck, boolean grpall) {
        UIvparts    pv;
        int         i;

        pv = null;
        for(i = 0; i < pms.length; i++) {
            if (pms[i].param == pa) {
                pv = pms[i];
                break;
            }
        }
        if (pv == null)
            return;
        if (grpall) {
            for(i = 0; i < pms.length; i++) {
                if (abs(pms[i].grp) == abs(pv.grp))
                    pms[i].locked = lck;
            }
        }
        else {
            pv.locked = lck;
        }
        // cursor should point a unlocked param.
        if (pms[cursor].locked)
            curmov(false, 1);
    }

    void
    kbd(char kin) {
        UIparam    p;
        int        len;

        p = pms[cursor].param;
        if (p.typeSel())
            return;    //   UIparamSel

        len = ksb.length();
        if (kin == ESC) {
            kclean();
            focus = false;
            return;
        }

        if (kin == DELETE || kin == BACKSPACE) {
            if (len > 0)
                ksb.deleteCharAt(len - 1);
            return;
        }

        if (kin == ENTER || kin == RETURN) {
            if (len > 0)
                p.setval(ksb);
            kclean();
            focus = false;
            return;
        }

        if (p.appendchk(ksb, kin)) {
            ksb.append(kin);
            focus = true;
        }
    }


    void
    mswheel(int x, int y, int val, boolean sft) {
        UIparam    p;

        if (focus)
            return;

        if (x < scr0.gx1)
            return;

        if (sft)
            val *= 100;
        p = tgtparam();
        p.chgval(false, val);
    }

    void
    msclick(int x, int y, boolean press, int btn, boolean shift) {
        UIvparts   p, ptgt;
        int        i, itgt;

        if (press == false)
            return;

        if (btn != 1)
            return;

        ptgt = null;
        itgt = -1;
        for(i = 0; i < pms.length; i++) {
            p = pms[i];
            if (p.locked)
                continue;
            if (p.mx0 <= x && x <= p.mx1 && p.my0 <= y && y <= p.my1) {
                itgt = i;
                ptgt = p;
                break;
            }
        }

        if (itgt >= 0) {
            if ((ptgt.attr & 0x0001) != 0) {
                if (itgt != cursor)
                    curset(itgt);
            }
            if (itgt == cursor) {
                if (ptgt.param.typeSel()) {
                    ptgt.param.chgval(false, ((shift) ? -1 : 1));
                }
                else if (! focus) {
                    focus = true;
                    ksb.append(ptgt.param.valstrraw(true));
                }
            }
            else {
                curset(itgt);
            }
        }
        else if (focus) {
            focus = false;
            kclean();
        }
    }

    void
    disp(int xofs, int yofs) {
        UIvparts   p;
        String     s;
        int        i, x, c;

        textAlign(LEFT, TOP);
        for(i = 0; i < pms.length; i++) {
            p = pms[i];

            c = (p.locked) ? 128 : 255;

            stroke(c, c, c);
            fill(c);

            s = p.param.valstr();
            x = p.dx;
            if (p.mx0 < 0) {  // set mouse area
                p.mx0 = x + int(xofs);
                p.my0 = p.dy + int(yofs);
                p.mx1 = p.mx0 + 80;
                p.my1 = p.my0 + 14;
            }
            if (cursor == i) {
                if (p.param.typeSel())
                    fill(0, 0, 120);
                else {
                    if (focus) {
                        fill(255, 255, 0);
                        c = 0;
                        s = ksb.toString();
                    }
                    else
                        fill(0, 140, 0);
                }
                noStroke();
                rect(p.mx0, p.my0, p.mx1 - p.mx0, p.my1 - p.my0);
            }
            fill(c);
            //text(s, x + xofs, p.dy + yofs);
            text(s, x + xofs + 5, p.dy + yofs);
            if (p.tx > 0) {
                fill(0);
                text(p.name, x - p.tx + xofs, p.dy + yofs);
            }
        }
    }
}


UIparamSel  pm_equiv = new UIparamSel(1, true, new UIsvpair[] {
                 new UIsvpair("off", 0),
                 new UIsvpair("on",  1),                  });

UIparamSel  pm_dispdots = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("off", 0),
                 new UIsvpair("on",  1),                  });


// for MINTIA scope, set default 7 to 8 (2ms/div to 1ms/div)
UIparamSel  pm_hdiv  = new UIparamSel(8, false, new UIsvpair[] {
                 new UIsvpair("500ms/div",17),
                 new UIsvpair("200ms/div",16),
                 new UIsvpair("100ms/div",15),
                 new UIsvpair("50ms/div",14),
                 new UIsvpair("20ms/div",13),
                 new UIsvpair("10ms/div",12),
                 new UIsvpair("5ms/div",11),
                 new UIsvpair("2ms/div",10),  // original default
                 new UIsvpair("1ms/div", 9),  // current default
                 new UIsvpair("500us/div", 8),
                 new UIsvpair("200us/div", 7),
                 new UIsvpair("100us/div", 6),
                 new UIsvpair("50us/div", 5),
                 new UIsvpair("20us/div", 4),
                 new UIsvpair("10us/div", 3),
                 new UIsvpair("5us/div", 2),
                 new UIsvpair("2us/div", 1),
                 new UIsvpair("1us/div", 0), });


UIparamNum  pm_hofs  = new UIparamNum("div", 0, -2000, 1000, 0, 2);

UIparamSel  pm_hmag  = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("x1" ,  1),
                 new UIsvpair("x2" ,  2),
                 new UIsvpair("x5" ,  5),
                 new UIsvpair("x10", 10),                 });

UIparamSel  pm_hscan = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("roll",  0),
                 new UIsvpair("wipe",  1),                 });

UIparamSel  pm_mode  = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("CH1" , 0),
                 new UIsvpair("CH2" , 1),
                 new UIsvpair("DUAL", 2),                  });

UIparamSel  pm_tsrc  = (board == 1 ) ? new UIparamSel(3, true, new UIsvpair[] {
                                                new UIsvpair("CH1" , 0),
                                                new UIsvpair("CH2" , 1),
                                                new UIsvpair("EXT" , 2),
                                                new UIsvpair("FG"  , 3), })
                                     : new UIparamSel(0, true, new UIsvpair[] {
                                                new UIsvpair("CH1" , 0),
                                                new UIsvpair("CH2" , 1),
                                                new UIsvpair("EXT" , 2), });

UIparamSel  pm_tmode = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("auto"  , 0),
                 new UIsvpair("normal", 1),
                 new UIsvpair("single", 2),                });


class UIparamNum_tlvl extends UIparamNum {
    private int request;

    UIparamNum_tlvl() {
        super("volts", 0, 0, 255, 0, 2);
        request = 0;
    }
    String  valstrraw(boolean foredit) {
        String    s;
        int       v;

        v = scr0.conv_tlvl(pm_tsrc.valnum());
        if (v >= 0) {
            if (! foredit)
                ps.printf(" ");
        }
        else {
            v = -v;
            ps.printf("-");
        }
        ps.printf("%1d.%02d", v / 100, v % 100);
        s = bs.toString();
        bs.reset();
        return  s;
    }

    void rstval() {
        request = 255;
        action();
    }

    void setval0(int newval) {
        request = -(constrain(newval, 0, 255) + 1);  // -256..-1
        action();
    }

    void setval(int newval) {
        int    ch;

        ch = pm_tsrc.valnum();
        newval = newval * 255 / pm_vref.valnum();
        if (board == 1 && ch < 2) {
            newval /= 2;
            if (ch == 0 && (d89old & 2) == 0)
                newval += 128;
            if (ch == 1 && (d89old & 1) == 0)
                newval += 128;
        }
        setval0(newval);
    }

    void setval2(int newval) {
        val = constrain(newval, 0, 255);
    }

    void chgval(boolean sft, int add) {
        if (add == 0)
            return;
        request = add / 2;
        if (request == 0)
            request = (add > 0) ? 1 : -1;
        request = 60 + constrain(request, -50, 50);  // 10..110
        action();
    }

    int valreq() {
        int    ret;
        ret = request;
        request = 0;
        return  ret;
    }
}
UIparamNum_tlvl  pm_tlvl = new UIparamNum_tlvl();


UIparamSel  pm_tslpe = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("rising", 0),
                 new UIsvpair("falling", 1),               });

UIparamNum  pm_tdly = new UIparamNum("us", 100, 100, 30000);

UIparamNum  pm_ch1ofs = new UIparamNum("div", 0, -9000, 9000, 0, 2);

UIparamNum  pm_ch1var = new UIparamNum(null, 1000, 400,  1000, 1000, 3);

UIparamSel  pm_ch1div = new UIparamSel(2, false, new UIsvpair[] {
                 new UIsvpair("5.0v/div",   200),
                 new UIsvpair("2.0v/div",   500),
                 new UIsvpair("1.0v/div",  1000),
                 new UIsvpair("0.5v/div",  2000),
                 new UIsvpair("0.2v/div",  5000),
                 new UIsvpair("0.1v/div", 10000),
                 new UIsvpair("50mv/div", 20000),
                 new UIsvpair("20mv/div", 50000),
                 new UIsvpair("10mv/div",100000),         });

UIparamSel  pm_ch1inv = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("off",  0),
                 new UIsvpair("on",   1),                 });

UIparamNum  pm_ch1gaindc = new UIparamNum(null, def_ch1gain_dc, 100, 20000,  def_ch1gain_dc, 3);
UIparamNum  pm_ch1gainac = new UIparamNum(null, def_ch1gain_ac, 100, 20000,  def_ch1gain_ac, 3);

UIparamSel  pm_ch1coup = new UIparamSel(def_ch1coup, true, new UIsvpair[] {
                 new UIsvpair("dc",   0),
                 new UIsvpair("ac",   1),});

UIparamNum  pm_ch2ofs = (board == 0) ? new UIparamNum("div", -500, -9000, 9000, -500, 2)
                                     : new UIparamNum("div",    0, -9000, 9000,    0, 2);

UIparamNum  pm_ch2var = new UIparamNum(null, 1000, 400,  1000, 1000, 3);

UIparamSel  pm_ch2div = new UIparamSel(2, false, new UIsvpair[] {
                 new UIsvpair("5.0v/div",   200),
                 new UIsvpair("2.0v/div",   500),
                 new UIsvpair("1.0v/div",  1000),
                 new UIsvpair("0.5v/div",  2000),
                 new UIsvpair("0.2v/div",  5000),
                 new UIsvpair("0.1v/div", 10000),
                 new UIsvpair("50mv/div", 20000),
                 new UIsvpair("20mv/div", 50000),
                 new UIsvpair("10mv/div",100000),           });

UIparamSel  pm_ch2inv = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("off",  0),
                 new UIsvpair("on",   1),                 });

UIparamNum  pm_ch2gaindc = new UIparamNum(null, def_ch2gain_dc, 100, 20000,  def_ch2gain_dc, 3);
UIparamNum  pm_ch2gainac = new UIparamNum(null, def_ch2gain_ac, 100, 20000,  def_ch2gain_ac, 3);

UIparamSel  pm_ch2coup = new UIparamSel(def_ch2coup, true, new UIsvpair[] {
                 new UIsvpair("dc",   0),
                 new UIsvpair("ac",   1),});

UIparamSel  pm_fftver = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("off"      ,  -1),
                 new UIsvpair("v(0-p)"   ,   0),
                 new UIsvpair("v(rms)"   ,   2),
                 new UIsvpair("dBV(0-p)" ,   1),
                 new UIsvpair("dBV(rms)" ,   3),          });

UIparamSel  pm_fftsig = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("CH1",  0),
                 new UIsvpair("CH2",  1),});

UIparamSel  pm_fftwin = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("rectangular", 0),
                 new UIsvpair("hanning",   1),
                 new UIsvpair("hamming",   2),
                 new UIsvpair("blackman",  3),
                 new UIsvpair("flat-top",  4),            });

UIparamNum  pm_fftofs = new UIparamNum("div", -200, -9000, 9000, -200, 2);

UIparamNum  pm_fftvar = new UIparamNum(null, 1000, 400,  1000, 1000, 3);

class UIparamSel_fdv extends UIparamSel {
    final UIsvpair[]  pairs2;

    UIparamSel_fdv(int iidx, UIsvpair p1[], UIsvpair p2[]) {
        super(iidx, false, p1);
        pairs2 = p2;
    }

    private UIsvpair[] psel() {
        int    v = pm_fftver.valnum();

        return  (v == 1 || v == 3) ? pairs2 : pairs;
    }

    String valstr() {
        UIsvpair    p[] = psel();
        return  " " + p[idx].s;
    }

    int valnum() {
        UIsvpair    p[] = psel();
        return  p[idx].v;
    }
}


UIparamSel  pm_fftdiv = new UIparamSel_fdv(2,
               new UIsvpair[] {
                 new UIsvpair("5.0v/div",   200),  // val / 1000
                 new UIsvpair("2.0v/div",   500),
                 new UIsvpair("1.0v/div",  1000),
                 new UIsvpair("0.5v/div",  2000),
                 new UIsvpair("0.2v/div",  5000),
                 new UIsvpair("0.1v/div", 10000),
                 new UIsvpair("50mv/div", 20000),
                 new UIsvpair("20mv/div", 50000),
                 new UIsvpair("10mv/div",100000), },
               new UIsvpair[] {
                 new UIsvpair("100dB/div",  10),  // val / 1000
                 new UIsvpair("50dB/div",   20),
                 new UIsvpair("20dB/div",   50),
                 new UIsvpair("10dB/div",  100),
                 new UIsvpair("5.0dB/div", 200),
                 new UIsvpair("2.0dB/div", 500),
                 new UIsvpair("1.0dB/div",1000),
                 new UIsvpair("0.5dB/div",2000),
                 new UIsvpair("0.2dB/div",5000), });


UIparamNum  pm_ofreq = new UIparamNum("hz", 1000, 31, 2000000);

UIparamNum  pm_oduty = new UIparamNum("%", 50, 0, 100);

UIparamSel  pm_fgwav = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("sine"     , 0),
                 new UIsvpair("triangle" , 1),
                 new UIsvpair("pulse"    , 2),                  });

UIparamNum  pm_fgfrq = new UIparamNum("hz", 1000,    3, 840000,  1000, 1);
UIparamNum  pm_fgdty = new UIparamNum("%",    50,     0,   100);

class UIparamNum_fg extends UIparamNum {
    UIparamNum_fg(String inm, int ival, int imin, int imax) {
        super(inm, ival, imin, imax);
    }
    UIparamNum_fg(String inm, int ival, int imin, int imax, int irst) {
        super(inm, ival, imin, imax, irst);
    }
    UIparamNum_fg(String inm, int ival, int imin, int imax, int irst, int idec) {
        super(inm, ival, imin, imax, irst, idec);
    }
    private int getvref() {
        return  pm_vref.valnum();
    }
    String valstrraw(boolean foredit) {
        String    s;
        char      c;
        int       tmp, vt;

        c = (val < 0) ? '-' : ' ';
        tmp = abs(val);
        vt = (getvref() * tmp + 250) / 500;
        
        switch(decimal) {
        default:  ps.printf("%c%d(%c%d)", c, tmp, c, vt);  break;
        case  1:  ps.printf("%c%d.%01d(%c%d.%01d)",
                            c, tmp/10, tmp%10, c, vt/10, vt%10);  break;
        case  2:  ps.printf("%c%d.%02d(%c%d.%02d)",
                            c, tmp/100, tmp%100, c, vt/100, vt%100);  break;
        }
        s = bs.toString();
        bs.reset();
        //if (nmunit != null)
        //    s += nmunit;
        return  s;
    }
}
UIparamNum_fg  pm_fgamp = new UIparamNum_fg("v", 500,   0, 500, 500, 2);
UIparamNum_fg  pm_fgofs = new UIparamNum_fg("v", 250,-250, 750, 250, 2);
UIparamNum_fg  pm_fgbch = new UIparamNum_fg("v", 250,   0, 500, 250, 2);

UIparamSel  pm_fgmem = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("M0" , 0),
                 new UIsvpair("M1" , 1),
                 new UIsvpair("M2" , 2),
                 new UIsvpair("M3" , 3),            }, -1);

UIparamNum    pm_vref = new UIparamNum("volts", 500,  300, 600,  500, 2);
// for MINTIA scope, parameter of ch1biasdc (DC offset)
// UIparamNum_fg pm_ch1biasdc = new UIparamNum_fg("v", def_ch1bias_dc,   0, 500, def_ch1bias_dc, 2);
UIparamNum pm_ch1biasdc = new UIparamNum(null, def_ch1bias_dc,   0, 500, def_ch1bias_dc);
UIparamNum_fg pm_ch1biasac = new UIparamNum_fg("v", def_ch1bias_ac,   0, 500, def_ch1bias_ac, 2);
// for MINTIA scope, DC offset of ch2 is same as ch1
// UIparamNum_fg pm_ch2biasdc = new UIparamNum_fg("v", def_ch2bias_dc,   0, 500, def_ch2bias_dc, 2);
UIparamNum pm_ch2biasdc = new UIparamNum(null, def_ch1bias_dc,   0, 500, def_ch1bias_dc);
UIparamNum_fg pm_ch2biasac = new UIparamNum_fg("v", def_ch2bias_ac,   0, 500, def_ch2bias_ac, 2);


class UIparamSel_inc extends UIparamSel {
    private int       keta;  // 0..5
    private int       dec;

    UIparamSel_inc() {
        super(0, false, null);
        keta = dec = 0;
    }

    void dec(int idec) {
        dec = constrain(idec, 0, 3);
    }

    void rstval() {
        keta = dec = 0;
        action();
    }

    void chgval(boolean sft, int add) {
        int    nx;

        if (add == 0)
            return;
        nx = keta + ((add > 0) ? 1 : -1);
        nx = constrain(nx, 0, 5);
        if (keta != nx) {
            keta = nx;
            action();
        }
    }

    String valstr() {
        final String[][]  disp = {
            {"     1" ,"    10" ,"   100" ,"  1000" ," 10000" ,"100000" },
            {"    0.1","    1.0","   10.0","  100.0"," 1000.0","10000.0"},
            {"   0.01","   0.10","   1.00","  10.00"," 100.00","1000.00"},
            {"  0.001","  0.010","  0.100","  1.000"," 10.000","100.000"},
        };
        return  disp[dec][keta];
    }

    int valnum() {
        int    i, r;

        r = 1;
        for(i = 0; i < keta; i++)
            r *= 10;
        return  r;
    }
}

UIparamSel_inc  pm_inc    = new UIparamSel_inc();

UIparamSel  pm_capbtn = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("go",  0),
                 new UIsvpair("go",  1),                    });

UIparamSel  pm_caparea = new UIparamSel(1, true, new UIsvpair[] {
                 new UIsvpair("full" , 0),
                 new UIsvpair("small", 1),                  });

UIparamSel  pm_folder = new UIparamSel(0, true, new UIsvpair[] {
                 new UIsvpair("sketch folder" , 0),
                 new UIsvpair("desktop"       , 1),
                 new UIsvpair("Downloads"     , 2),         });

UIparamStr pm_fname = new UIparamStr("oscillo-scr");


UIvparts myui[] = {
    new UIvparts(  1, 794, 69,   0, 0x00, "signal"      , pm_mode  ),

    new UIvparts(  2, 794,140,   0, 0x00, "volts/div"   , pm_ch1div),
    new UIvparts( -2, 794,161,   0, 0x00, "position"    , pm_ch1ofs),
    new UIvparts( -2, 794,182,   0, 0x00, "variable"    , pm_ch1var),
    new UIvparts( -2, 794,203,   0, 0x00, "invert"      , pm_ch1inv),
    new UIvparts( -2, 794,224, 104, 0x0c, "coupling"    , pm_ch1coup),

    new UIvparts(  3, 794,286,   0, 0x00, "volts/div"   , pm_ch2div),
    new UIvparts( -3, 794,307,   0, 0x00, "position"    , pm_ch2ofs),
    new UIvparts( -3, 794,328,   0, 0x00, "variable"    , pm_ch2var),
    new UIvparts( -3, 794,349,   0, 0x00, "invert"      , pm_ch2inv),
    new UIvparts( -3, 794,370, 104, 0x0c, "coupling"    , pm_ch2coup),

    new UIvparts(  4, 794,431,   0, 0x00, "vertical"    , pm_fftver),
    new UIvparts( -4, 794,452,   0, 0x00, "signal"      , pm_fftsig),
    new UIvparts( -4, 794,473,   0, 0x00, "vertical/div", pm_fftdiv),
    new UIvparts( -4, 794,494,   0, 0x00, "position"    , pm_fftofs),
    new UIvparts( -4, 794,515,   0, 0x00, "variable"    , pm_fftvar),
    new UIvparts( -4, 794,536,   0, 0x00, "window"      , pm_fftwin),

    new UIvparts( -5,1066, 45, 104, 0x00, 1, "capture"  , pm_capbtn),
    new UIvparts( -5,1066, 60, 104, 0x00, "size"        , pm_caparea),
    new UIvparts( -5,1066, 75, 104, 0x00, "folder"      , pm_folder),
    new UIvparts( -5,1066, 90, 104, 0x00, "filename"    , pm_fname),

    new UIvparts(  6,1066,140,   0, 0x00, "time/div"    , pm_hdiv  ),
    new UIvparts( -6,1066,161,   0, 0x00, "position"    , pm_hofs  ),
    new UIvparts( -6,1066,182,   0, 0x00, "mag"         , pm_hmag  ),
    new UIvparts( -6,1066,203,   0, 0x00, "scan"        , pm_hscan ),

    new UIvparts(  7,1066,242,   0, 0x00, "source"      , pm_tsrc  ),
    new UIvparts( -7,1066,263,   0, 0x00, "mode"        , pm_tmode ),
    new UIvparts( -7,1066,284,   0, 0x00, "level"       , pm_tlvl  ),
    new UIvparts( -7,1066,305,   0, 0x00, "slope"       , pm_tslpe  ),
    new UIvparts( -7,1066,326,   0, 0x00, "delay"       , pm_tdly  ),

// move (0, -10) for MINTIA scope to insert "offset calib" below
    new UIvparts(  8,1066,357,   0, 0x00, "freq"        , pm_ofreq),
    new UIvparts( -8,1066,378,   0, 0x00, "duty"        , pm_oduty),

// append "offset calib" for MINTIA scope
    new UIvparts(-10,1066,411,   0, 0x00, "offset calib", pm_ch1biasdc),
    new UIvparts(-10,1066,432,   0, 0x00, "equiv"       , pm_equiv ),
    new UIvparts(-10,1066,453,   0, 0x00, "dots"        , pm_dispdots),

    new UIvparts(-10,1066,474,   0, 0x00, "vref calib"  , pm_vref),

    new UIvparts(-10,1066,495,   0, 0x00, "inc unit"    , pm_inc),

    new UIvparts(-10, 980,516,  80, 0x08, "dc-gain  ch1", pm_ch1gaindc),
    new UIvparts(-10, 980,531,  80, 0x08, "dc-bias  ch1", pm_ch1biasdc),
    new UIvparts(-10, 980,546,  80, 0x08, "ac-gain  ch1", pm_ch1gainac),
    new UIvparts(-10, 980,561,  80, 0x08, "ac-bias  ch1", pm_ch1biasac),

    new UIvparts(-10,1100,516,  28, 0x08, "ch2"         , pm_ch2gaindc),
    new UIvparts(-10,1100,531,  28, 0x08, "ch2"         , pm_ch2biasdc),
    new UIvparts(-10,1100,546,  28, 0x08, "ch2"         , pm_ch2gainac),
    new UIvparts(-10,1100,561,  28, 0x08, "ch2"         , pm_ch2biasac),
};

UIman uiman = new UIman(myui);


PImage img0, img1;

void
draw()
{
    background(0, 0, 0);

    if (bootstep < 0) {
        bootstep++;
        image(img0, 0, 0);
        textSize(14);  // for MINTIA scope, affect whole script
        text(relname, 1120, 622);  // for MINTIA scope
        return;
    }

    if (! scibuf0.isOpened()) {
        scibuf0.open(this, null);
        image(img0, 0, 0);
        text(relname, 1120, 622);  // for MINTIA scope
        return;
    }

    scibuf0.receive();

    if (setcfgflg > 0) {
        switch(bootstep) {
        case  0:  // host just started
            bootstep = 2;
            pm_mode.setidx(-1); // set oscillo params
            pm_hdiv.setidx(-1);
            pm_ch1coup.setidx(-1);
            pm_ch2coup.setidx(-1);
            break;
        case  1:  // tgt restarted
            bootstep = 3;
            pm_tlvl.setval0(tgt_tlvl);    // set oscillo params
            break;

        case  2:
            bootstep = 4;
            if (fgendipsw >= 0)
                genc.memread(fgendipsw);
            break;

        case  3:
            bootstep = 9;
            if (fgendipsw >= 0)
                pm_fgwav.setidx(-1);
            break;

        case  4:
            bootstep = 9;
            if (fgendipsw >= 0)
                pm_fgmem.setidx(fgendipsw);
            break;

        default:
        case  9:
            break;
        }
    }

    mskey.dowheel();
    mskey.measure();

    if (board == 1) {
        pm_ch1coup.setidx_noact((d89old & 2) != 0 ? 0 : 1);  // d89hack
        pm_ch2coup.setidx_noact((d89old & 1) != 0 ? 0 : 1);  // d89hack
    }

    doactions();
    scibuf0.comsend();

    {
        String    s;

        if (pm_fgmem == uiman.tgtparam() && genc.minfo != null)
            s = "fgen-mem: " + genc.minfo;
        else
            s = null;
        scr0.fgenmsg(s);
    }

    image(img1, 0, 0);
    scr0.grid();

    smpdisp = smphold.getdisp();
    if (smpdisp != null) {
        scr0.dispsig(smpdisp);
        scr0.dispfft(smpdisp);
        scr0.dispinfo(smpdisp);
        scr0.dispmeasure(smpdisp);
    }
    pm_inc.dec(uiman.decimalinfo());
    uiman.disp(0, 0);

    if (capscr.request(-1)) {
        if (smphold.ifstopped())
            capscr.take(pm_caparea.valnum(), pm_folder.valnum(), pm_fname.valstr());
        capscr.request(0);
    }
    capscr.anime();
    text(relname, 1120, 608);  // for MINTIA scope, 12pix shift?
}


class MouseKey {
    final ByteArrayOutputStream    bs;
    final PrintStream              ps;
    int    wheel;
    int    m0x, m0y, m1x, m1y, msts;
    boolean  keyshift, keyctrl;


    MouseKey() {
        bs = new ByteArrayOutputStream();
        ps = new PrintStream(bs);
        wheel = 0;
        msts = 0;
        keyshift = keyctrl = false;
    }

    synchronized void wheel(float val) {
        int   delta;

        delta = (int)val;
        wheel += delta;
    }

    synchronized int getwheel() {
        int    ret;

        ret = wheel;
        wheel = 0;
        return  ret;
    }

    void dowheel() {
        int    val;
        val = getwheel();
        if (val != 0)
            uiman.mswheel(mouseX, mouseY, val, keyshift);
    }

    void measure() {
        switch(msts) {
        default: scr0.measure_req(0, 0, 0, 0, 0);            break;
        case  1:
        case  2: scr0.measure_req(1, 0, 0, mouseX, mouseY);  break;
        case  3: scr0.measure_req(2, m0x, m0y, m1x, m1y);    break;
        }
    }

    void pressed() {
        int    btn;

        btn = (mouseButton == LEFT) ? 1 : 0;

        if (scr0.gx0 <= mouseX && mouseX <= scr0.gx1) {
            if (scr0.gy0 <= mouseY && mouseY <= scr0.gy1) {
                if (btn == 1) {
                    msts = 2;
                    m0x = mouseX;
                    m0y = mouseY;
                    cursor(CROSS);
                }
            }
            else if (mouseY >= 90 && mouseY < scr0.gy0 && abs(mouseX - (int)(scr0.ox + scr0.wx / 2)) < 30) {
                if (btn == 1) {
                    if (smphold.ifstopped())
                        smphold.resume(false);
                    else
                        smphold.stop();
                    uiman.lock(pm_capbtn, !smphold.ifstopped());
                }
            }
        }
        // for MINTIA scope, change color change position
        // else if (mouseX >= 1045 && mouseX < 1078 && mouseY >= 594 && mouseY < 614) {
        else if (mouseX >= 601 && mouseX < 658 && mouseY >= 569 && mouseY < 626) {
            scr0.colchg();
        }
        else {
            uiman.msclick(mouseX, mouseY, true, btn, keyshift);
        }
    }

    private void moved_sub() {
        int    x, y, mode;

        if (msts < 2) {
            x = mouseX;
            y = mouseY;
            msts = 0;
            mode = ARROW;
            if (scr0.gx0 <= x && x <= scr0.gx1)
                if (scr0.gy0 <= y && y <= scr0.gy1 ) {
                    msts = 1;
                    mode = CROSS;
            }
            cursor(mode);
        }
    }

    void released() {
        int    btn;

        btn = (mouseButton == LEFT) ? 1 : 0;

        if (msts > 0) {
            msts = 0;
            moved_sub();
        }
        else {
            uiman.msclick(mouseX, mouseY, false, btn, keyshift);
        }
    }

    void moved() {
        moved_sub();
    }
    void dragged() {
        if (msts > 1) {
            msts = 3;
            m1x  = mouseX;
            m1y  = mouseY;
        }
    }

    void keyreleased() {
        if (key == CODED) {
            if (keyCode == SHIFT)
                keyshift = false;
            else if (keyCode == CONTROL)
                keyctrl = false;
        }
    }

    void keypressed() {
        if (key == CODED) {
            if (keyCode == SHIFT) {
                keyshift = true;
                return;
            }
            else if (keyCode == CONTROL) {
                keyctrl = true;
                return;
            }
        }

        if (uiman.focus()) {
            uiman.kbd(key);
            return;
        }

        switch(key){
        default:
            uiman.kbd(key);
            break;

        case 'p':
        case 'P':
            capscr.request(1);
            break;

        case 'r':
        case 'R':
            uiman.rstval(key == 'R');
            break;

        case 'W':
        case 'M':
        case ' ':
            if (uiman.tgtparam() == pm_fgmem) {
                int    i;

                i = pm_fgmem.valnum();
                if (key == 'W')
                    genc.memwrite(i);
                else
                    genc.memread(i);
            }
            else if (key == ' ') {
                if (smphold.ifstopped())
                    smphold.resume(false);
                else
                    smphold.stop();
                uiman.lock(pm_capbtn, !smphold.ifstopped());
            }
            break;

        case TAB:
            uiman.curmov(keyshift, 1);
            break;

        case RETURN:
        case ENTER:
            if (uiman.tgtparam().typeSel())
                uiman.chgval(false, (keyshift) ? -1 : 1);
            break;

        case CODED:
            switch(keyCode){
            case UP:
                uiman.curmov(keyshift, -1);
                break;
            case DOWN:
                uiman.curmov(keyshift,  1);
                break;
            case RIGHT:
              if (keyshift)
                  pm_inc.chgval(false, 1);
              else
                  uiman.chgval(false, pm_inc.valnum());
              break;
            case LEFT:
              if (keyshift)
                  pm_inc.chgval(false, -1);
              else
                  uiman.chgval(false, -pm_inc.valnum());
              break;
            }
            break;
        }
    }
}

MouseKey mskey = new MouseKey();
void mousePressed()  {mskey.pressed(); }
void mouseReleased() {mskey.released();}
void mouseDragged()  {mskey.dragged(); }
void mouseMoved()    {mskey.moved();   }

void mouseWheel(MouseEvent event) {
    mskey.wheel(event.getCount());
}

void keyReleased()   {mskey.keyreleased();}
void keyPressed() {
    mskey.keypressed();
    if (key == ESC)
        key = 0;  // don't let them escape! 'from processing-wiki'
}


class OscCtrl extends UIaction {

    void doaction() {
        HorizonCfg   hc;
        int          flag;
        int          spd, inp, trig, treq, tlvl, tdly, ofrq, oduty;

        pm_tlvl.setval2(tgt_tlvl);

        flag = getflag();
        if (flag == 0)
            return;

        if (flagtest(flag, 0x800000) && pm_tmode.valnum() != 2)
            smphold.resume(false);

        hc = hzncfg[pm_hdiv.valnum()];
        spd = (pm_equiv.valnum() != 0) ? hc.idxequv : hc.idxreal;

        if (flagtest(flag, 0x0002)) {  // pm_hdiv
            uiman.lock(pm_hscan, (hc.idxreal != 8));
            uiman.lock(pm_equiv, (hc.idxreal == hc.idxequv));
        }

        //if (flagtest(flag, 0x0800)) {  // pm_ch1coup
        //    boolean  ac = (pm_ch1coup.valnum() != 0);
        //    uiman.lock(pm_ch1biasdc,  ac);
        //    uiman.lock(pm_ch1biasac, !ac);
        //}
        //if (flagtest(flag, 0x1000)) {  // pm_ch2coup
        //    boolean  ac = (pm_ch2coup.valnum() != 0);
        //    uiman.lock(pm_ch2biasdc,  ac);
        //    uiman.lock(pm_ch2biasac, !ac);
        //}

        if (flagtest(flag, 0x0102)) {  // pm_mode or pm_hdiv
            inp   = pm_mode.valnum();
            if (inp == 2 || spd == 8) {
                uiman.lock(pm_fftsig, false);
            }
            else {
                pm_fftsig.setidx(inp);
                uiman.lock(pm_fftsig, true);
            }
        }

        trig = pm_tsrc.valnum() & 7;
        trig |= (pm_tmode.valnum() != 0) ? 0x20 : 0x00;
        trig |= (pm_tslpe.valnum() != 0) ? 0x10 : 0x00;
        inp   = pm_mode.valnum();
        treq  = pm_tlvl.valreq();
        tlvl  = 0;
        if (treq < 0) {
            tlvl = -treq - 1;  // 0..255
            treq = 254;
        }
        tdly  = pm_tdly.valnum();  // 100..30000 usec
        ofrq  = pm_ofreq.valnum();
        oduty = pm_oduty.valnum();
        scibuf0.oscparams(spd, inp, trig, treq, tlvl, tdly, ofrq, oduty, 0);
    }
}


class FgenAction extends UIaction {
    int    flag;
    int    tmsent;

    void doaction() {
        Genparam    g;

        flag = getflag();
        if (flag == 0) {
            if (bootstep != 9) {
                tmsent = millis() + 600;
                return;
            }

            // don't set the values within 400msecs
            // just after sending a change request.
            // because it takes a while before the new values
            // are available in genc.gen.
            if ((millis() - tmsent) < 400)
                return;
            g = genc.gen;
            pm_fgwav.setidx_noact(g.wav );
            pm_fgfrq.setval_noact(g.freq);
            pm_fgdty.setval_noact(g.duty);
            pm_fgamp.setval_noact(g.amp );
            pm_fgofs.setval_noact(g.ofs );
            pm_fgbch.setval_noact(g.bch );
        }
        else if (flag == 0x01) {      // i.e.  pm_fgmem
            genc.memsel(pm_fgmem.valnum());
        }
        else {
            g = new Genparam();
            g.wav  = pm_fgwav.valnum();
            g.freq = pm_fgfrq.valnum();
            g.duty = pm_fgdty.valnum();
            g.amp  = pm_fgamp.valnum();
            g.ofs  = pm_fgofs.valnum();
            g.bch  = pm_fgbch.valnum();
            genc.genset(g);
            tmsent = millis();
        }
    }
}


class CaptureAction extends UIaction {

    void doaction() {
        if (getflag() != 0)
            capscr.request(1);
    }
}




class CaptureScreen
{
    private boolean    request;
    private int        dspcnt;
    private int        dspsub;
    final   int        dspbse;
    private int        lx, ly, wx, wy;

    CaptureScreen() {
        request = false;
        dspcnt  = 0;
        dspsub  = 0;
        dspbse  = 60;
        lx = ly = wx = wy = 0;
    }

    private void
    initanime(int cnt, int ilx, int ily, int iwx, int iwy)
    {
        dspcnt = constrain(cnt, 0, 10);
        lx = ilx;
        ly = ily;
        wx = iwx;
        wy = iwy;
        dspsub = (dspcnt > 0) ? (255 - dspbse) / dspcnt : 0;
    }

    boolean
    request(int cmd)
    {
        if (cmd == 1)
            request = true;
        else if (cmd == 0)
            request = false;
        return  request;
    }

    void
    anime()
    {
        int    br;

        if (dspcnt == 0)
            return;

        br = dspcnt * dspsub + dspbse;
        br = constrain(br, dspbse, 255);

        dspcnt--;
        pushStyle();
        blendMode(ADD);
        noStroke();
        fill(br);
        rect(lx, ly, wx, wy);
        popStyle();
    }

    boolean
    desktop()
    {
        File    dir;
        dir = new File(System.getProperty("user.home"), "Desktop");
        return  dir.isDirectory();
    }

    boolean
    downloads()  // append for MINTIA scope
    {
        File    dir;
        dir = new File(System.getProperty("user.home"), "Downloads");
        return  dir.isDirectory();
    }

    boolean
    take(int type, int folder, String fname)
    {
        IOException    excp;
        File           dir, tmpf;
        boolean        ok;
        long           filesz;
        int            x, y, w, h;

        if (folder == 1)  { // desktop
            //    get Desktop (for windows, mac, Ubuntu)
            dir = new File(System.getProperty("user.home"), "Desktop");
        }
        else if (folder == 2)  { // Downloads
            //    get Desktop (for mac, windows, Ubuntu)
            dir = new File(System.getProperty("user.home"), "Downloads");
        }
        else  {             // sketch folder
            //    get SketchDir
            //    to absorb the difference between Processing2 and Processing3
            //        [ideal]  dir    = new File(sketchPath());
            dir = new File(sketchPath("dummy"));
            dir = dir.getParentFile();
        }

        tmpf   = null;
        excp   = null;
        ok     = false;
        filesz = 0;

        x = y = w = h = 0;

        for(int i = 0; i < 201; i++) {
            String    tmp;

            tmp = (i == 0) ? fname : fname + "_" + i;
            tmp += ".png";
            tmpf = new File(dir, tmp);
            try {
                if (tmpf.createNewFile()) {
                    ok = true;
                    break;
                }
            } catch(IOException e) {
                excp = e;
                break;
            }
        }

        if (ok) {
            PImage   tmpimg;

            if (type == 1) {
                x =  56;
                y =  77;
                w = 520;
                h = 520;
            }
            else {
                x = 0;
                y = 0;
                w = width;
                h = height;
            }
            tmpimg = get(x, y, w, h);
            tmpimg.save(tmpf.getAbsolutePath());
            //tmpimg.save(tmpf.getName());
            filesz = tmpf.length();
        }

        if (filesz == 0) {
            System.out.printf("Capture Screen failed.\n");
            if (excp != null) {
                System.out.printf("  reason: %s\n", excp.getMessage());
            }
            System.out.printf("  file  : %s\n", tmpf.getPath());
            return  false;
        }
        initanime(4, x, y, w, h);
        System.out.printf("\007Capture Screen(%7d bytes) to \"%s\"\n", filesz, tmpf.getPath());
        return  true;
    }
}

CaptureScreen  capscr = new CaptureScreen();


class OsCheck
{
    private int    ostype;   // 0:mac 1:win 2:linux

    OsCheck() 
    {
        String    tmps;

        tmps = System.getProperty("os.name").toLowerCase();
        if (tmps.startsWith("mac os x"))
            ostype = 0;
        else if (tmps.startsWith("windows"))
            ostype = 1;
        else
            ostype = 2;
    }

    int type()
    {
        return  ostype;
    }

    boolean isMac()
    {
        return  ostype == 0;
    }

    boolean isWindows()
    {
        return  ostype == 1;
    }

    boolean isLinux()
    {
        return  ostype == 2;
    }
}

OsCheck  oschk = new OsCheck();


void
setup2()
{
    //size(1200, 640);

    if (board == 1) {
        pm_ch1coup.setrst(1);
        pm_ch2coup.setrst(1);
        pm_ch1gaindc.setrst(500);
        pm_ch1biasdc.setrst(  0);
        pm_ch1gainac.setrst(500);
        pm_ch1biasac.setrst(250);
        pm_ch2gaindc.setrst(500);
        pm_ch2biasdc.setrst(  0);
        pm_ch2gainac.setrst(500);
        pm_ch2biasac.setrst(250);
        pm_ch1coup.rstval();
        pm_ch2coup.rstval();
        pm_ch1gaindc.rstval();
        pm_ch1biasdc.rstval();
        pm_ch1gainac.rstval();
        pm_ch1biasac.rstval();
        pm_ch2gaindc.rstval();
        pm_ch2biasdc.rstval();
        pm_ch2gainac.rstval();
        pm_ch2biasac.rstval();
    }

    stroke(255);
    background(0, 0, 0);

    img0 = loadImage("MINTIAscope0.png");
    img1 = loadImage("MINTIAscope2.png");
    if (img0 == null || img1 == null) {
        System.out.printf("Image data read error.\n");
        exit();
    }

    scr0 = new Scr(10, 10);
    smphold = new Smphold();
    smpdisp = null;
    smpread = smphold.getread(false);

    crc0 = new Crc8();
    crc1 = new Crc8();

    pktin = -1;

    //addMouseWheelListener(new java.awt.event.MouseWheelListener() {
    //    public void mouseWheelMoved(java.awt.event.MouseWheelEvent evt) { 
    //        mskey.wheel(evt);
    //}}); 
 
    {
        OscCtrl       osc = new OscCtrl();
        FgenAction    fga = new FgenAction();
        CaptureAction cap = new CaptureAction();

        pm_hdiv.register(  osc, 0x000002);
        pm_equiv.register( osc, 0x000004);
        pm_tsrc.register(  osc, 0x800008);
        pm_tmode.register( osc, 0x800010);
        pm_tlvl.register(  osc, 0x800020);
        pm_tslpe.register(  osc, 0x800040);
        pm_tdly.register(  osc, 0x800080);
        pm_mode.register(  osc, 0x000100);
        pm_ofreq.register( osc, 0x000200);
        pm_oduty.register( osc, 0x000400);

        //pm_ch1coup.register(osc,0x000800);
        //pm_ch2coup.register(osc,0x001000);

        pm_hdiv.action();

        pm_fgmem.register(fga, 0x01);
        pm_fgwav.register(fga, 0x02);
        pm_fgfrq.register(fga, 0x04);
        pm_fgdty.register(fga, 0x08);
        pm_fgamp.register(fga, 0x10);
        pm_fgofs.register(fga, 0x20);
        pm_fgbch.register(fga, 0x40);

        pm_capbtn.register(cap, 0x01);
        uiman.lock(pm_capbtn, true);

       if (capscr.desktop())
            pm_folder.setidx_noact(2);  // for MINTIA scope, set default to Downloads
        else
            uiman.lock(pm_folder, true);
    }

    bootstep = -10;

    System.out.printf("Setup done!\n");
}


class Crc8 {
        final int crc8tbl[] = {
            0x00, 0x85, 0x8F, 0x0A, 0x9B, 0x1E, 0x14, 0x91,
            0xB3, 0x36, 0x3C, 0xB9, 0x28, 0xAD, 0xA7, 0x22,
            0xE3, 0x66, 0x6C, 0xE9, 0x78, 0xFD, 0xF7, 0x72,
            0x50, 0xD5, 0xDF, 0x5A, 0xCB, 0x4E, 0x44, 0xC1,
            0x43, 0xC6, 0xCC, 0x49, 0xD8, 0x5D, 0x57, 0xD2,
            0xF0, 0x75, 0x7F, 0xFA, 0x6B, 0xEE, 0xE4, 0x61,
            0xA0, 0x25, 0x2F, 0xAA, 0x3B, 0xBE, 0xB4, 0x31,
            0x13, 0x96, 0x9C, 0x19, 0x88, 0x0D, 0x07, 0x82,
        
            0x86, 0x03, 0x09, 0x8C, 0x1D, 0x98, 0x92, 0x17,
            0x35, 0xB0, 0xBA, 0x3F, 0xAE, 0x2B, 0x21, 0xA4,
            0x65, 0xE0, 0xEA, 0x6F, 0xFE, 0x7B, 0x71, 0xF4,
            0xD6, 0x53, 0x59, 0xDC, 0x4D, 0xC8, 0xC2, 0x47,
            0xC5, 0x40, 0x4A, 0xCF, 0x5E, 0xDB, 0xD1, 0x54,
            0x76, 0xF3, 0xF9, 0x7C, 0xED, 0x68, 0x62, 0xE7,
            0x26, 0xA3, 0xA9, 0x2C, 0xBD, 0x38, 0x32, 0xB7,
            0x95, 0x10, 0x1A, 0x9F, 0x0E, 0x8B, 0x81, 0x04,
        
            0x89, 0x0C, 0x06, 0x83, 0x12, 0x97, 0x9D, 0x18,
            0x3A, 0xBF, 0xB5, 0x30, 0xA1, 0x24, 0x2E, 0xAB,
            0x6A, 0xEF, 0xE5, 0x60, 0xF1, 0x74, 0x7E, 0xFB,
            0xD9, 0x5C, 0x56, 0xD3, 0x42, 0xC7, 0xCD, 0x48,
            0xCA, 0x4F, 0x45, 0xC0, 0x51, 0xD4, 0xDE, 0x5B,
            0x79, 0xFC, 0xF6, 0x73, 0xE2, 0x67, 0x6D, 0xE8,
            0x29, 0xAC, 0xA6, 0x23, 0xB2, 0x37, 0x3D, 0xB8,
            0x9A, 0x1F, 0x15, 0x90, 0x01, 0x84, 0x8E, 0x0B,
        
            0x0F, 0x8A, 0x80, 0x05, 0x94, 0x11, 0x1B, 0x9E,
            0xBC, 0x39, 0x33, 0xB6, 0x27, 0xA2, 0xA8, 0x2D,
            0xEC, 0x69, 0x63, 0xE6, 0x77, 0xF2, 0xF8, 0x7D,
            0x5F, 0xDA, 0xD0, 0x55, 0xC4, 0x41, 0x4B, 0xCE,
            0x4C, 0xC9, 0xC3, 0x46, 0xD7, 0x52, 0x58, 0xDD,
            0xFF, 0x7A, 0x70, 0xF5, 0x64, 0xE1, 0xEB, 0x6E,
            0xAF, 0x2A, 0x20, 0xA5, 0x34, 0xB1, 0xBB, 0x3E,
            0x1C, 0x99, 0x93, 0x16, 0x87, 0x02, 0x08, 0x8D,
        };

    int    crcreg;

    int
    calc(int dat) {
        if (dat < 0) {
            dat = crcreg;
            crcreg = 0x00;
        }
        else  {
            crcreg = crc8tbl[crcreg ^ dat];
            dat = crcreg;
        }
        return  dat;
    }
}


//  FFT routine derived from fft4g.c written by Takuya OOURA
//  http://www.kurims.kyoto-u.ac.jp/~ooura/fftman/ftmndl.html
//
//  I appreciate the FFT routines written by Mr. OOURA.


class FFT {
    double    wa[]  = new double[512];
    double    aa[]  = new double[1024];
    int      ipa[]  = new int[50];

    FFT() {
        ipa[0] = 0;
    }

    void fft(int typ, int n, float fa[]) { // n must be power of 2
        int       i, j;
        double    fv;

        for(i = 0; i < n; i++)
            aa[i] = window(typ, i, n, (double)fa[i]);
        rdft(n, 1, aa);
        for(i = 0; i < n; i++) {
            fv = aa[i] / n;
            if (i > 1)
                fv += fv;  // add the alias
            fv *= fv;
            fa[i] = (float)fv;
        }

        fv = fa[1];  // save
        j = 1;
        for(i = 2; i < n; i += 2)
            fa[j++] = fa[i] + fa[i + 1];
        fa[j] = (float)fv;  // restore

        n >>= 1;
        for(j = 0; j <= n; j++) {
            if (fa[j] < 1.0e-6)
                fa[j] = 1.0e-6;
        }
    }


    private double window(int typ, int idx, int num, double val) {
        double    rad, cs, cs2, win, acf;

        rad = 2.0 * Math.PI * (double)idx / (double)num;
        cs  = Math.cos(rad);
        switch(typ) {
        default:
        case  0: win = 1.0;                           // rectangular
                 acf = 1.0;
                 break;
        case  1: win = 0.50 - 0.50 * cs;              // hanning
                 acf = 0.50;
                 break;
        case  2: win = 0.54 - 0.46 * cs;              // hamming
                 acf = 0.54;
                 break;
        case  3: cs2 = Math.cos(2.0 * rad);           // blackman
                 win = 0.42 - 0.50 * cs + 0.08 * cs2;
                 acf = 0.42;
                 break;
        case  4: cs2 = Math.cos(2.0 * rad);           // flat-top
                 win = 1.0 - 1.933 * cs + 1.286 * cs2;
                 win -= 0.3880 * Math.cos(3.0 * rad);
                 win += 0.0322 * Math.cos(4.0 * rad);
                 // the formula already contains amp correction factor.
                 acf = 1.0;
                 break;
        }
        return  val * win / acf;
    }

    private void rdft(int n, int isgn, double a[])
    {
        int nw, nc;
        double xi;

        nw = ipa[0];
        if (n > (nw << 2)) {
            nw = n >> 2;
            makewt(nw, ipa, wa);
        }
        nc = ipa[1];
        if (n > (nc << 2)) {
            nc = n >> 2;
            makect(nc, ipa, wa, nw);
        }
        if (isgn >= 0) {
            if (n > 4) {
                bitrv2(n, ipa, 2, a);
                cftfsub(n, a, wa);
                rftfsub(n, a, nc, wa, nw);
            } else if (n == 4) {
                cftfsub(n, a, wa);
            }
            xi = a[0] - a[1];
            a[0] += a[1];
            a[1] = xi;
        } else {
            a[1] = 0.5 * (a[0] - a[1]);
            a[0] -= a[1];
            if (n > 4) {
                rftbsub(n, a, nc, wa, nw);
                bitrv2(n, ipa, 2, a);
                cftbsub(n, a, wa);
            } else if (n == 4) {
                cftfsub(n, a, wa);
            }
        }
    }


    /* -------- initializing routines -------- */


    //#include <math.h>

    private void makewt(int nw, int ip[], double w[])
    {
        int j, nwh;
        double delta, x, y;
    
        ip[0] = nw;
        ip[1] = 1;
        if (nw > 2) {
            nwh = nw >> 1;
            delta = Math.atan(1.0) / nwh;
            w[0] = 1;
            w[1] = 0;
            w[nwh] = Math.cos(delta * nwh);
            w[nwh + 1] = w[nwh];
            if (nwh > 2) {
                for (j = 2; j < nwh; j += 2) {
                    x = Math.cos(delta * j);
                    y = Math.sin(delta * j);
                    w[j] = x;
                    w[j + 1] = y;
                    w[nw - j] = y;
                    w[nw - j + 1] = x;
                }
                bitrv2(nw, ip, 2, w);
            }
        }
    }


    private void makect(int nc, int ip[], double c[], int nw)
    {
        int j, nch;
        double delta;
    
        ip[1] = nc;
        if (nc > 1) {
            nch = nc >> 1;
            delta = Math.atan(1.0) / nch;
            c[nw] = Math.cos(delta * nch);
            c[nch + nw] = 0.5 * c[nw];
            for (j = 1; j < nch; j++) {
                c[j + nw] = 0.5 * Math.cos(delta * j);
                c[nc - j + nw] = 0.5 * Math.sin(delta * j);
            }
        }
    }


    /* -------- child routines -------- */

    private void bitrv2(int n, int ip[], int ipofs, double a[])
    {
        int j, j1, k, k1, l, m, m2;
        double xr, xi, yr, yi;
    
        ip[ipofs] = 0;
        l = n;
        m = 1;
        while ((m << 3) < l) {
            l >>= 1;
            for (j = 0; j < m; j++) {
                ip[m + j + ipofs] = ip[j + ipofs] + l;
            }
            m <<= 1;
        }
        m2 = 2 * m;
        if ((m << 3) == l) {
            for (k = 0; k < m; k++) {
                for (j = 0; j < k; j++) {
                    j1 = 2 * j + ip[k + ipofs];
                    k1 = 2 * k + ip[j + ipofs];
                    xr = a[j1];
                    xi = a[j1 + 1];
                    yr = a[k1];
                    yi = a[k1 + 1];
                    a[j1] = yr;
                    a[j1 + 1] = yi;
                    a[k1] = xr;
                    a[k1 + 1] = xi;
                    j1 += m2;
                    k1 += 2 * m2;
                    xr = a[j1];
                    xi = a[j1 + 1];
                    yr = a[k1];
                    yi = a[k1 + 1];
                    a[j1] = yr;
                    a[j1 + 1] = yi;
                    a[k1] = xr;
                    a[k1 + 1] = xi;
                    j1 += m2;
                    k1 -= m2;
                    xr = a[j1];
                    xi = a[j1 + 1];
                    yr = a[k1];
                    yi = a[k1 + 1];
                    a[j1] = yr;
                    a[j1 + 1] = yi;
                    a[k1] = xr;
                    a[k1 + 1] = xi;
                    j1 += m2;
                    k1 += 2 * m2;
                    xr = a[j1];
                    xi = a[j1 + 1];
                    yr = a[k1];
                    yi = a[k1 + 1];
                    a[j1] = yr;
                    a[j1 + 1] = yi;
                    a[k1] = xr;
                    a[k1 + 1] = xi;
                }
                j1 = 2 * k + m2 + ip[k + ipofs];
                k1 = j1 + m2;
                xr = a[j1];
                xi = a[j1 + 1];
                yr = a[k1];
                yi = a[k1 + 1];
                a[j1] = yr;
                a[j1 + 1] = yi;
                a[k1] = xr;
                a[k1 + 1] = xi;
            }
        } else {
            for (k = 1; k < m; k++) {
                for (j = 0; j < k; j++) {
                    j1 = 2 * j + ip[k + ipofs];
                    k1 = 2 * k + ip[j + ipofs];
                    xr = a[j1];
                    xi = a[j1 + 1];
                    yr = a[k1];
                    yi = a[k1 + 1];
                    a[j1] = yr;
                    a[j1 + 1] = yi;
                    a[k1] = xr;
                    a[k1 + 1] = xi;
                    j1 += m2;
                    k1 += m2;
                    xr = a[j1];
                    xi = a[j1 + 1];
                    yr = a[k1];
                    yi = a[k1 + 1];
                    a[j1] = yr;
                    a[j1 + 1] = yi;
                    a[k1] = xr;
                    a[k1 + 1] = xi;
                }
            }
        }
    }


    private void cftfsub(int n, double a[], double w[])
    {
        int j, j1, j2, j3, l;
        double x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;
    
        l = 2;
        if (n > 8) {
            cft1st(n, a, w);
            l = 8;
            while ((l << 2) < n) {
                cftmdl(n, l, a, w);
                l <<= 2;
            }
        }
        if ((l << 2) == n) {
            for (j = 0; j < l; j += 2) {
                j1 = j + l;
                j2 = j1 + l;
                j3 = j2 + l;
                x0r = a[j] + a[j1];
                x0i = a[j + 1] + a[j1 + 1];
                x1r = a[j] - a[j1];
                x1i = a[j + 1] - a[j1 + 1];
                x2r = a[j2] + a[j3];
                x2i = a[j2 + 1] + a[j3 + 1];
                x3r = a[j2] - a[j3];
                x3i = a[j2 + 1] - a[j3 + 1];
                a[j] = x0r + x2r;
                a[j + 1] = x0i + x2i;
                a[j2] = x0r - x2r;
                a[j2 + 1] = x0i - x2i;
                a[j1] = x1r - x3i;
                a[j1 + 1] = x1i + x3r;
                a[j3] = x1r + x3i;
                a[j3 + 1] = x1i - x3r;
            }
        } else {
            for (j = 0; j < l; j += 2) {
                j1 = j + l;
                x0r = a[j] - a[j1];
                x0i = a[j + 1] - a[j1 + 1];
                a[j] += a[j1];
                a[j + 1] += a[j1 + 1];
                a[j1] = x0r;
                a[j1 + 1] = x0i;
            }
        }
    }


    private void cftbsub(int n, double a[], double w[])
    {
        int j, j1, j2, j3, l;
        double x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;
    
        l = 2;
        if (n > 8) {
            cft1st(n, a, w);
            l = 8;
            while ((l << 2) < n) {
                cftmdl(n, l, a, w);
                l <<= 2;
            }
        }
        if ((l << 2) == n) {
            for (j = 0; j < l; j += 2) {
                j1 = j + l;
                j2 = j1 + l;
                j3 = j2 + l;
                x0r = a[j] + a[j1];
                x0i = -a[j + 1] - a[j1 + 1];
                x1r = a[j] - a[j1];
                x1i = -a[j + 1] + a[j1 + 1];
                x2r = a[j2] + a[j3];
                x2i = a[j2 + 1] + a[j3 + 1];
                x3r = a[j2] - a[j3];
                x3i = a[j2 + 1] - a[j3 + 1];
                a[j] = x0r + x2r;
                a[j + 1] = x0i - x2i;
                a[j2] = x0r - x2r;
                a[j2 + 1] = x0i + x2i;
                a[j1] = x1r - x3i;
                a[j1 + 1] = x1i - x3r;
                a[j3] = x1r + x3i;
                a[j3 + 1] = x1i + x3r;
            }
        } else {
            for (j = 0; j < l; j += 2) {
                j1 = j + l;
                x0r = a[j] - a[j1];
                x0i = -a[j + 1] + a[j1 + 1];
                a[j] += a[j1];
                a[j + 1] = -a[j + 1] - a[j1 + 1];
                a[j1] = x0r;
                a[j1 + 1] = x0i;
            }
        }
    }


    private void cft1st(int n, double a[], double w[])
    {
        int j, k1, k2;
        double wk1r, wk1i, wk2r, wk2i, wk3r, wk3i;
        double x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;
    
        x0r = a[0] + a[2];
        x0i = a[1] + a[3];
        x1r = a[0] - a[2];
        x1i = a[1] - a[3];
        x2r = a[4] + a[6];
        x2i = a[5] + a[7];
        x3r = a[4] - a[6];
        x3i = a[5] - a[7];
        a[0] = x0r + x2r;
        a[1] = x0i + x2i;
        a[4] = x0r - x2r;
        a[5] = x0i - x2i;
        a[2] = x1r - x3i;
        a[3] = x1i + x3r;
        a[6] = x1r + x3i;
        a[7] = x1i - x3r;
        wk1r = w[2];
        x0r = a[8] + a[10];
        x0i = a[9] + a[11];
        x1r = a[8] - a[10];
        x1i = a[9] - a[11];
        x2r = a[12] + a[14];
        x2i = a[13] + a[15];
        x3r = a[12] - a[14];
        x3i = a[13] - a[15];
        a[8] = x0r + x2r;
        a[9] = x0i + x2i;
        a[12] = x2i - x0i;
        a[13] = x0r - x2r;
        x0r = x1r - x3i;
        x0i = x1i + x3r;
        a[10] = wk1r * (x0r - x0i);
        a[11] = wk1r * (x0r + x0i);
        x0r = x3i + x1r;
        x0i = x3r - x1i;
        a[14] = wk1r * (x0i - x0r);
        a[15] = wk1r * (x0i + x0r);
        k1 = 0;
        for (j = 16; j < n; j += 16) {
            k1 += 2;
            k2 = 2 * k1;
            wk2r = w[k1];
            wk2i = w[k1 + 1];
            wk1r = w[k2];
            wk1i = w[k2 + 1];
            wk3r = wk1r - 2 * wk2i * wk1i;
            wk3i = 2 * wk2i * wk1r - wk1i;
            x0r = a[j] + a[j + 2];
            x0i = a[j + 1] + a[j + 3];
            x1r = a[j] - a[j + 2];
            x1i = a[j + 1] - a[j + 3];
            x2r = a[j + 4] + a[j + 6];
            x2i = a[j + 5] + a[j + 7];
            x3r = a[j + 4] - a[j + 6];
            x3i = a[j + 5] - a[j + 7];
            a[j] = x0r + x2r;
            a[j + 1] = x0i + x2i;
            x0r -= x2r;
            x0i -= x2i;
            a[j + 4] = wk2r * x0r - wk2i * x0i;
            a[j + 5] = wk2r * x0i + wk2i * x0r;
            x0r = x1r - x3i;
            x0i = x1i + x3r;
            a[j + 2] = wk1r * x0r - wk1i * x0i;
            a[j + 3] = wk1r * x0i + wk1i * x0r;
            x0r = x1r + x3i;
            x0i = x1i - x3r;
            a[j + 6] = wk3r * x0r - wk3i * x0i;
            a[j + 7] = wk3r * x0i + wk3i * x0r;
            wk1r = w[k2 + 2];
            wk1i = w[k2 + 3];
            wk3r = wk1r - 2 * wk2r * wk1i;
            wk3i = 2 * wk2r * wk1r - wk1i;
            x0r = a[j + 8] + a[j + 10];
            x0i = a[j + 9] + a[j + 11];
            x1r = a[j + 8] - a[j + 10];
            x1i = a[j + 9] - a[j + 11];
            x2r = a[j + 12] + a[j + 14];
            x2i = a[j + 13] + a[j + 15];
            x3r = a[j + 12] - a[j + 14];
            x3i = a[j + 13] - a[j + 15];
            a[j + 8] = x0r + x2r;
            a[j + 9] = x0i + x2i;
            x0r -= x2r;
            x0i -= x2i;
            a[j + 12] = -wk2i * x0r - wk2r * x0i;
            a[j + 13] = -wk2i * x0i + wk2r * x0r;
            x0r = x1r - x3i;
            x0i = x1i + x3r;
            a[j + 10] = wk1r * x0r - wk1i * x0i;
            a[j + 11] = wk1r * x0i + wk1i * x0r;
            x0r = x1r + x3i;
            x0i = x1i - x3r;
            a[j + 14] = wk3r * x0r - wk3i * x0i;
            a[j + 15] = wk3r * x0i + wk3i * x0r;
        }
    }


    private void cftmdl(int n, int l, double a[], double w[])
    {
        int j, j1, j2, j3, k, k1, k2, m, m2;
        double wk1r, wk1i, wk2r, wk2i, wk3r, wk3i;
        double x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;
    
        m = l << 2;
        for (j = 0; j < l; j += 2) {
            j1 = j + l;
            j2 = j1 + l;
            j3 = j2 + l;
            x0r = a[j] + a[j1];
            x0i = a[j + 1] + a[j1 + 1];
            x1r = a[j] - a[j1];
            x1i = a[j + 1] - a[j1 + 1];
            x2r = a[j2] + a[j3];
            x2i = a[j2 + 1] + a[j3 + 1];
            x3r = a[j2] - a[j3];
            x3i = a[j2 + 1] - a[j3 + 1];
            a[j] = x0r + x2r;
            a[j + 1] = x0i + x2i;
            a[j2] = x0r - x2r;
            a[j2 + 1] = x0i - x2i;
            a[j1] = x1r - x3i;
            a[j1 + 1] = x1i + x3r;
            a[j3] = x1r + x3i;
            a[j3 + 1] = x1i - x3r;
        }
        wk1r = w[2];
        for (j = m; j < l + m; j += 2) {
            j1 = j + l;
            j2 = j1 + l;
            j3 = j2 + l;
            x0r = a[j] + a[j1];
            x0i = a[j + 1] + a[j1 + 1];
            x1r = a[j] - a[j1];
            x1i = a[j + 1] - a[j1 + 1];
            x2r = a[j2] + a[j3];
            x2i = a[j2 + 1] + a[j3 + 1];
            x3r = a[j2] - a[j3];
            x3i = a[j2 + 1] - a[j3 + 1];
            a[j] = x0r + x2r;
            a[j + 1] = x0i + x2i;
            a[j2] = x2i - x0i;
            a[j2 + 1] = x0r - x2r;
            x0r = x1r - x3i;
            x0i = x1i + x3r;
            a[j1] = wk1r * (x0r - x0i);
            a[j1 + 1] = wk1r * (x0r + x0i);
            x0r = x3i + x1r;
            x0i = x3r - x1i;
            a[j3] = wk1r * (x0i - x0r);
            a[j3 + 1] = wk1r * (x0i + x0r);
        }
        k1 = 0;
        m2 = 2 * m;
        for (k = m2; k < n; k += m2) {
            k1 += 2;
            k2 = 2 * k1;
            wk2r = w[k1];
            wk2i = w[k1 + 1];
            wk1r = w[k2];
            wk1i = w[k2 + 1];
            wk3r = wk1r - 2 * wk2i * wk1i;
            wk3i = 2 * wk2i * wk1r - wk1i;
            for (j = k; j < l + k; j += 2) {
                j1 = j + l;
                j2 = j1 + l;
                j3 = j2 + l;
                x0r = a[j] + a[j1];
                x0i = a[j + 1] + a[j1 + 1];
                x1r = a[j] - a[j1];
                x1i = a[j + 1] - a[j1 + 1];
                x2r = a[j2] + a[j3];
                x2i = a[j2 + 1] + a[j3 + 1];
                x3r = a[j2] - a[j3];
                x3i = a[j2 + 1] - a[j3 + 1];
                a[j] = x0r + x2r;
                a[j + 1] = x0i + x2i;
                x0r -= x2r;
                x0i -= x2i;
                a[j2] = wk2r * x0r - wk2i * x0i;
                a[j2 + 1] = wk2r * x0i + wk2i * x0r;
                x0r = x1r - x3i;
                x0i = x1i + x3r;
                a[j1] = wk1r * x0r - wk1i * x0i;
                a[j1 + 1] = wk1r * x0i + wk1i * x0r;
                x0r = x1r + x3i;
                x0i = x1i - x3r;
                a[j3] = wk3r * x0r - wk3i * x0i;
                a[j3 + 1] = wk3r * x0i + wk3i * x0r;
            }
            wk1r = w[k2 + 2];
            wk1i = w[k2 + 3];
            wk3r = wk1r - 2 * wk2r * wk1i;
            wk3i = 2 * wk2r * wk1r - wk1i;
            for (j = k + m; j < l + (k + m); j += 2) {
                j1 = j + l;
                j2 = j1 + l;
                j3 = j2 + l;
                x0r = a[j] + a[j1];
                x0i = a[j + 1] + a[j1 + 1];
                x1r = a[j] - a[j1];
                x1i = a[j + 1] - a[j1 + 1];
                x2r = a[j2] + a[j3];
                x2i = a[j2 + 1] + a[j3 + 1];
                x3r = a[j2] - a[j3];
                x3i = a[j2 + 1] - a[j3 + 1];
                a[j] = x0r + x2r;
                a[j + 1] = x0i + x2i;
                x0r -= x2r;
                x0i -= x2i;
                a[j2] = -wk2i * x0r - wk2r * x0i;
                a[j2 + 1] = -wk2i * x0i + wk2r * x0r;
                x0r = x1r - x3i;
                x0i = x1i + x3r;
                a[j1] = wk1r * x0r - wk1i * x0i;
                a[j1 + 1] = wk1r * x0i + wk1i * x0r;
                x0r = x1r + x3i;
                x0i = x1i - x3r;
                a[j3] = wk3r * x0r - wk3i * x0i;
                a[j3 + 1] = wk3r * x0i + wk3i * x0r;
            }
        }
    }


    private void rftfsub(int n, double a[], int nc, double c[], int nw)
    {
        int j, k, kk, ks, m;
        double wkr, wki, xr, xi, yr, yi;
    
        m = n >> 1;
        ks = 2 * nc / m;
        kk = 0;
        for (j = 2; j < m; j += 2) {
            k = n - j;
            kk += ks;
            wkr = 0.5 - c[nc - kk + nw];
            wki = c[kk + nw];
            xr = a[j] - a[k];
            xi = a[j + 1] + a[k + 1];
            yr = wkr * xr - wki * xi;
            yi = wkr * xi + wki * xr;
            a[j] -= yr;
            a[j + 1] -= yi;
            a[k] += yr;
            a[k + 1] -= yi;
        }
    }


    private void rftbsub(int n, double a[], int nc, double c[], int nw)
    {
        int j, k, kk, ks, m;
        double wkr, wki, xr, xi, yr, yi;
    
        a[1] = -a[1];
        m = n >> 1;
        ks = 2 * nc / m;
        kk = 0;
        for (j = 2; j < m; j += 2) {
            k = n - j;
            kk += ks;
            wkr = 0.5 - c[nc - kk + nw];
            wki = c[kk + nw];
            xr = a[j] - a[k];
            xi = a[j + 1] + a[k + 1];
            yr = wkr * xr + wki * xi;
            yi = wkr * xi - wki * xr;
            a[j] -= yr;
            a[j + 1] = yi - a[j + 1];
            a[k] += yr;
            a[k + 1] = yi - a[k + 1];
        }
        a[m + 1] = -a[m + 1];
    }
}

FFT  fft = new FFT();
