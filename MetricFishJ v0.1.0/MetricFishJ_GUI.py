from javax.swing import SwingWorker, JFrame, JPanel, JLabel, JButton, ImageIcon, BorderFactory, JOptionPane
from java.awt import Font, GridLayout, GridBagLayout, Color, BorderLayout, GridBagConstraints, Insets
from javax.swing.border import EtchedBorder
from ij import IJ
import sys

## MetricFishJ version
version = "v0.1.0"

## Path to MetricFishJ
plugin_path = IJ.getDir("plugins") + "/MetricFishJ v0.1.0/"

## Install the macros
macros_path = plugin_path + "macros.ijm"
IJ.run("Install...", "install=[" + macros_path + "]")

## Main window
frame = JFrame("MetricFishJ " + version)
frame.setResizable(False)

## Panel 1 - Morphometric measurements
panelMens = JPanel(GridBagLayout())
panelMens.setBorder(
    BorderFactory.createTitledBorder(
    BorderFactory.createEtchedBorder(
        EtchedBorder.RAISED, Color.GRAY, Color.DARK_GRAY), "Morphometric measurements"))
panelMens.getBorder().setTitleFont(Font("Dialog", Font.BOLD, 15))

## Panel 4 - Actions (Help)
panelActions = JPanel(GridBagLayout())

## Panel 5 - Vertical wrapper
panelAll = JPanel(GridLayout(0, 1))

## Panel 6 - Logo (placed ONLY ONCE in the whole GUI)
panelLogo = JPanel(GridBagLayout())

## Action bound to each button
macro = ""

class TraitTask(SwingWorker) :
    def doInBackground(self) :
        # Run the macro in a SwingWorker thread
        try:
            IJ.run(macro)
        except:
            Type, value = sys.exc_info()[:2]
            if "Macro canceled" not in str(value):
                print 'Error:', str(Type)
                print 'value:', str(value)

def runMacro(name):
    global macro
    macro = name
    TraitTask().execute()

def MT(event):
   runMacro("MetricFishJ Traits v1 EN")

def MTM(event):
   runMacro("MetricFishJ Traits Multi v1 EN")

def MCont(event):
   runMacro("MetricFishJ Continue v1 EN")

def showHelp(event):
   msg = ("<html><body style='width: 420px;'>"
          "<b>Morphometric measurements</b><br>"
          "44 measurements from side-view images: scale, outline, lines D/A/H/E,<br>"
          "then landmarks clicked one by one. Results in the &laquo; Traits &raquo; table.<br><br>"
          "<b>Single image</b>: analyzes the currently open image.<br>"
          "<b>Multiple images</b>: processes a whole folder, with an optional pause<br>"
          "between each image.<br>"
          "<b>Continue</b>: resumes an interrupted measurement (dialog closed by<br>"
          "mistake).<br><br>"
          "The manual is in the MetricFishJ v0.1.0 folder."
          "</body></html>")
   JOptionPane.showMessageDialog(frame, msg, "Help - MetricFishJ", JOptionPane.INFORMATION_MESSAGE)

def scaledImageIcon(path, w):
   """
   Create a resized ImageIcon from an image

   Args:
       path (str): The path to the image
       w (int): The target width

   Returns:
       A resized ImageIcon
   """
   I = ImageIcon(path)
   I = I.getImage()
   sI = I.getScaledInstance(w, -1, I.SCALE_SMOOTH)
   return ImageIcon(sI)

CENTER = GridBagConstraints.CENTER
HORIZ = GridBagConstraints.HORIZONTAL

# --- Panel 1: Morphometric measurements ---
bMensUnique = JButton("Single image")
bMensUnique.addActionListener(MT)
bMensUnique.setFont(Font("Dialog", Font.BOLD, 14))
bMensUnique.setToolTipText("Analyze the currently open image")

bMensMulti = JButton("Multiple images")
bMensMulti.addActionListener(MTM)
bMensMulti.setFont(Font("Dialog", Font.BOLD, 14))
bMensMulti.setToolTipText("Start a new analysis on a folder of images")

bMensCont = JButton("Continue")
bMensCont.addActionListener(MCont)
bMensCont.setFont(Font("Dialog", Font.BOLD, 14))
bMensCont.setToolTipText("Resume an interrupted measurement")

panelMens.add(bMensUnique, GridBagConstraints(0, 0, 1, 1, 0.33, 0.0, CENTER, HORIZ, Insets(8, 10, 8, 5), 0, 0))
panelMens.add(bMensMulti, GridBagConstraints(1, 0, 1, 1, 0.33, 0.0, CENTER, HORIZ, Insets(8, 5, 8, 5), 0, 0))
panelMens.add(bMensCont, GridBagConstraints(2, 0, 1, 1, 0.33, 0.0, CENTER, HORIZ, Insets(8, 5, 8, 10), 0, 0))

# --- Panel 4: Actions (Help) ---
bHelp = JButton("Help")
bHelp.addActionListener(showHelp)
bHelp.setFont(Font("Dialog", Font.BOLD, 13))

panelActions.add(bHelp, GridBagConstraints(0, 0, 1, 1, 1.0, 0.0, CENTER, HORIZ, Insets(6, 10, 6, 10), 0, 0))

# --- Panel 6: Logo (only occurrence of the icon in the whole GUI) ---
iconLogo = JLabel(scaledImageIcon(plugin_path + "Icons/MetricFishJ_logo.png", 55))
labelLogo = "<html>MetricFishJ " + version + " &ndash; OWO Nicolas Roland, 2026 &ndash; based on MorFishJ v0.3.0 (Mattia Ghilardi, 2025)</html>"
lLogo = JLabel(labelLogo)
lLogo.setFont(Font("Dialog", Font.BOLD, 13))

panelLogo.add(iconLogo, GridBagConstraints(0, 0, 1, 1, 0.1, 0.0, CENTER, HORIZ, Insets(5, 15, 5, 0), 0, 0))
panelLogo.add(lLogo, GridBagConstraints(1, 0, 1, 1, 0.9, 0.0, CENTER, HORIZ, Insets(5, 10, 5, 15), 0, 0))

## Assembly
panelAll.add(panelMens)
panelAll.add(panelActions)

frame.add(panelAll, BorderLayout.PAGE_START)
frame.add(panelLogo, BorderLayout.PAGE_END)
frame.pack()
frame.setVisible(True)
