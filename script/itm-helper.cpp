#include <cmath>
#include <iomanip>
#include <iostream>
#include <vector>

#include "itm.h"
#include "Enums.h"

int main() {
    double frequency, htx, hrx, climateValue, n0, polarization, epsilon, sigma;
    double confidence, reliability, watts, txGain, rxGain, pointCountValue, resolution;
    if (!(std::cin >> frequency >> htx >> hrx >> climateValue >> n0 >> polarization >> epsilon >> sigma
          >> confidence >> reliability >> watts >> txGain >> rxGain >> pointCountValue >> resolution)) return 2;
    const int pointCount = static_cast<int>(std::lround(pointCountValue));
    if (pointCountValue != pointCount || pointCount < 3 || pointCount > 501 || resolution <= 0) return 2;
    std::vector<double> pfl(static_cast<size_t>(pointCount) + 2);
    pfl[0] = pointCount - 1;
    pfl[1] = resolution;
    for (int i = 0; i < pointCount; ++i) {
        if (!(std::cin >> pfl[static_cast<size_t>(i) + 2]) || !std::isfinite(pfl[static_cast<size_t>(i) + 2])) return 2;
    }

    const int climate = static_cast<int>(std::lround(climateValue));
    const int pol = polarization >= 0.5 ? 1 : 0;
    double loss = 0;
    long warnings = 0;
    IntermediateValues intermediate{};
    const int status = ITM_P2P_CR_Ex(htx, hrx, pfl.data(), climate, n0, frequency, pol, epsilon, sigma,
                                     1, confidence, reliability, &loss, &warnings, &intermediate);
    if ((status != 0 && status != 1) || !std::isfinite(loss)) {
        std::cerr << "NTIA ITM error " << status << "\n";
        return 3;
    }
    const double receivedDBm = 10.0 * std::log10(watts * 1000.0) + txGain + rxGain - loss;
    const char *mode = intermediate.mode == MODE__LINE_OF_SIGHT ? "Visibilidad" :
                       intermediate.mode == MODE__DIFFRACTION ? "Difracción" :
                       intermediate.mode == MODE__TROPOSCATTER ? "Dispersión troposférica" : "Sin clasificar";
    std::cout << std::setprecision(12)
              << "{\"basicTransmissionLossDB\":" << loss
              << ",\"receivedPowerDBm\":" << receivedDBm
              << ",\"terrainIrregularityMeters\":" << intermediate.delta_h__meter
              << ",\"distanceKm\":" << intermediate.d__km
              << ",\"warningFlags\":" << warnings
              << ",\"propagationMode\":\"" << mode << "\"}\n";
    return 0;
}
