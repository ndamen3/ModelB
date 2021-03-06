import gab.opencv.*;
import processing.video.*;
import java.awt.*;
import processing.serial.*;

ArrayList<Contour> contours;
ArrayList<Contour> polygons;

float gamma = 1.7;

int numPorts=0;  // the number of serial ports in use
int maxPorts=24; // maximum number of serial ports

Serial[] ledSerial = new Serial[maxPorts];     // each port's actual Serial port
Rectangle[] ledArea = new Rectangle[maxPorts]; // the area of the movie each port gets, in % (0-100)
boolean[] ledLayout = new boolean[maxPorts];   // layout of rows, true = even is left->right
PImage[] ledImage = new PImage[maxPorts];      // image sent to each port
int[] gammatable = new int[256];
int errorCount=0;
float framerate=30.00;

int numLEDS = 175*12; // number of leds
int led = 0;
int inc=0;
float hue=175;
int sat=250;
int bright=255;

float facey;
float facex;
float mapy;
float mapx;


PVector[] LED = new PVector[numLEDS];


Capture video;
OpenCV opencv;

// x=y*width

void setup(){
  delay(20);
  //serialConfigure("COM5");
  
  //String[] cameras = Capture.list();
  
  if (errorCount > 0) exit();
  for (int i=0; i < 256; i++) {
    gammatable[i] = (int)(pow((float)i / 255.0, gamma) * 255.0 + 0.5);
  }
  
  size(175, 12);
  colorMode(HSB);
  background(180,255,255);
  loadPixels();

  
  for (int i=0; i<numLEDS; i++) {
    LED[i]= new PVector(0, 0);
  }
  
  
  video = new Capture(this, 320/2, 240/2);
  opencv = new OpenCV(this, 320/2, 240/2);
  opencv.loadCascade(OpenCV.CASCADE_FRONTALFACE);  

  video.start();
}

void draw(){
  background(175,255,255);
  scale(2);
  opencv.loadImage(video);
  loadPixels();
  
  Rectangle[] faces = opencv.detect();
  //println(faces.length);
  //float factor = map(d, 0,200,2,0);
  for (int i = 0; i < faces.length; i++) {
    //println(faces[i].x + "," + faces[i].y);
    mapy = map(faces[i].y,0,120,0,12);
    mapx = map(faces[i].x,0,160,0,170);
    println(mapx +" , "+mapy);
    
    stroke(0);
    strokeWeight(1);
    fill(hue,150,bright);
    
    ellipse(mapx, mapy, 3, 3);
    
    //for(int x = 0;x<width; x++){
    //  for(int y=0; y<height;y++){
    //    float d = dist(x,y,mapx,mapy);
    //    pixels[x+y*width]=color(d*4+hue,sat,bright-d);
    //  }
    // }
    } 
    
    
   // updatePixels();
    
  
  for (int i=0; i < numPorts; i++) {    
    // copy a portion of the movie's image to the LED image
    //int xoffset = percentage(video.width, ledArea[i].x);
    //int yoffset = percentage(video.height, ledArea[i].y);
    //int xwidth =  percentage(video.width, ledArea[i].width);
    //int yheight = percentage(video.height, ledArea[i].height);
    
    //Pushes the 
    //ledImage[i].copy(video, xoffset, yoffset, xwidth, yheight,0, 0, ledImage[i].width, ledImage[i].height);
    
    // should Push only the image held within ledImage[];
    ledImage[i].loadPixels();
    for (int j=0; j<175*12; j++) {
      ledImage[i].pixels[j]=pixels[j];
    }
    ledImage[i].updatePixels();                
                     
    // convert the LED image to raw data
    byte[] ledData =  new byte[(ledImage[i].width * ledImage[i].height * 3) + 3];
    image2data(ledImage[i], ledData, ledLayout[i]);
    if (i == 0) {
      ledData[0] = '*';  // first Teensy is the frame sync master
      int usec = (int)((1000000.0 / framerate) * 0.75);
      ledData[1] = (byte)(usec);   // request the frame sync pulse
      ledData[2] = (byte)(usec >> 8); // at 75% of the frame time
    } else {
      ledData[0] = '%';  // others sync to the master board
      ledData[1] = 0;
      ledData[2] = 0;
    }
    // send the raw data to the LEDs  :-)
    ledSerial[i].write(ledData); 
  }
  inc++;
  if(inc>100){
    inc = 0;
  }

}


void captureEvent(Capture c) {
  c.read();
}


// image2data converts an image to OctoWS2811's raw data format.
// The number of vertical pixels in the image must be a multiple
// of 8.  The data array must be the proper size for the image.
void image2data(PImage image, byte[] data, boolean layout) {
  int offset = 3;
  int x, y, xbegin, xend, xinc, mask;
  int linesPerPin = image.height / 8;
  int pixel[] = new int[8];
  
  for (y = 0; y < linesPerPin; y++) {
    if ((y & 1) == (layout ? 0 : 1)) {
      // even numbered rows are left to right
      xbegin = 0;
      xend = image.width;
      xinc = 1;
    } else {
      // odd numbered rows are right to left
      xbegin = image.width - 1;
      xend = -1;
      xinc = -1;
    }
    for (x = xbegin; x != xend; x += xinc) {
      for (int i=0; i < 8; i++) {
        // fetch 8 pixels from the image, 1 for each pin
        pixel[i] = image.pixels[x + (y + linesPerPin * i) * image.width];
        pixel[i] = colorWiring(pixel[i]);
      }
      // convert 8 pixels to 24 bytes
      for (mask = 0x800000; mask != 0; mask >>= 1) {
        byte b = 0;
        for (int i=0; i < 8; i++) {
          if ((pixel[i] & mask) != 0) b |= (1 << i);
        }
        data[offset++] = b;
      }
    }
  } 
}

// translate the 24 bit color from RGB to the actual
// order used by the LED wiring.  GRB is the most common.
int colorWiring(int c) {
  int red = (c & 0xFF0000) >> 16;
  int green = (c & 0x00FF00) >> 8;
  int blue = (c & 0x0000FF);
  red = gammatable[red];
  green = gammatable[green];
  blue = gammatable[blue];
  return (green << 16) | (red << 8) | (blue); // GRB - most common wiring
}


// ask a Teensy board for its LED configuration, and set up the info for it.
void serialConfigure(String portName) {
  if (numPorts >= maxPorts) {
    println("too many serial ports, please increase maxPorts");
    errorCount++;
    return;
  }
  try {
    ledSerial[numPorts] = new Serial(this, portName);
    if (ledSerial[numPorts] == null) throw new NullPointerException();
    ledSerial[numPorts].write('?');
  } catch (Throwable e) {
    println("Serial port " + portName + " does not exist or is non-functional");
    errorCount++;
    return;
  }
  delay(50);
  String line = ledSerial[numPorts].readStringUntil(10);
  if (line == null) {
    println("Serial port " + portName + " is not responding.");
    println("Is it really a Teensy 3.0 running VideoDisplay?");
    errorCount++;
    return;
  }
  String param[] = line.split(",");
  if (param.length != 12) {
    println("Error: port " + portName + " did not respond to LED config query");
    errorCount++;
    return;
  }
  // only store the info and increase numPorts if Teensy responds properly
  ledImage[numPorts] = new PImage(Integer.parseInt(param[0]), Integer.parseInt(param[1]), RGB);
  ledArea[numPorts] = new Rectangle(Integer.parseInt(param[5]), Integer.parseInt(param[6]),
                     Integer.parseInt(param[7]), Integer.parseInt(param[8]));
  ledLayout[numPorts] = (Integer.parseInt(param[5]) == 0);
  numPorts++;
}

// scale a number by a percentage, from 0 to 100
int percentage(int num, int percent) {
  double mult = percentageFloat(percent);
  double output = num * mult;
  return (int)output;
}

// scale a number by the inverse of a percentage, from 0 to 100
int percentageInverse(int num, int percent) {
  double div = percentageFloat(percent);
  double output = num / div;
  return (int)output;
}

// convert an integer from 0 to 100 to a float percentage
// from 0.0 to 1.0.  Special cases for 1/3, 1/6, 1/7, etc
// are handled automatically to fix integer rounding.
double percentageFloat(int percent) {
  if (percent == 33) return 1.0 / 3.0;
  if (percent == 17) return 1.0 / 6.0;
  if (percent == 14) return 1.0 / 7.0;
  if (percent == 13) return 1.0 / 8.0;
  if (percent == 11) return 1.0 / 9.0;
  if (percent ==  9) return 1.0 / 11.0;
  if (percent ==  8) return 1.0 / 12.0;
  return (double)percent / 100.0;
}
