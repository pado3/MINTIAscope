# MINTIAscope
simple PC oscilloscope based upon kit_scope, Arduino, Processing
<p>
  This is based upon kit_scope by Kyusyu Institute of Technology (Kyutech).<br />
  URL: http://www.iizuka.kyutech.ac.jp/faculty/physicalcomputing/pc_kitscope
</p><p>
  With my project, input range is expanded from 0~+5V to -9~+9V, input impedance is controlled to 1M-ohm.
</p><p>
  Its hardware is made with ATmega328P (with Arduino UNO bootloader), OP-AMP and charge pump circuit. <br />
  Its software is made with Arduino IDE and Processing.<br />
</p><p>
  Schetch for ATmega328P (kit_scope.ino) is used as published by Kyutech. Please download from their site.<br />
  I modified the Processing code (kit_scope.pde) in these points:<br />
  <ol>
    <li>change default value of gain & offset</li>
    <li>append offset CAL</li>
    <li>modify over-range treatment</li>
    <li>set default capture folder to Downloads</li>
    <li>make original skin</li>
    <li>larger font, show release name, change print color</li>
  </ol>
</p><p>
  I plan to write a blog on this subject.　Wait for moment, please.
</p>
