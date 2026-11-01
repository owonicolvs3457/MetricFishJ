# MetricFishJ v0.1.0

ImageJ/Fiji plugin for semi-automatic morphometric measurements of fish from side-view (lateral) photographs.

## Features
- **Single image**: measures the currently open image.
- **Multiple images**: batch processing of a folder, with an optional pause between images.
- **Continue**: resumes an interrupted measurement session.

For each specimen, set the scale, outline the fish, draw the reference lines (D/A/H/E), then click the anatomical landmarks one by one. The plugin computes 44 morphometric measurements, written to a "Traits" results table.

## Installation
1. Download this repository (**Code > Download ZIP**) or the release archive.
2. Copy the folder `MetricFishJ v0.1.0` into the `plugins` directory of ImageJ/Fiji.
3. Restart ImageJ/Fiji and launch the plugin from the Plugins menu.

The folder name must stay exactly `MetricFishJ v0.1.0`, because the interface script loads the macros from it.

## Citation
OWO, N. R. (2026). *MetricFishJ v0.1.0* [Software]. Zenodo. DOI: *(to be added after the Zenodo publication)*

## Credits
Author: OWO Nicolas Roland (ORCID: 0009-0005-6504-7920).
Based on MorFishJ v0.3.0 (Mattia Ghilardi, 2025).

## License
Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International (CC BY-NC-ND 4.0). See `MetricFishJ v0.1.0/License.md`.
