#include <cmath>
#include <vector>
#include "itm.h"
#include "Errors.h"

// Inputs match TerrainITMInput. No process/JSON round trip per map cell.
extern "C" int rw_itm_predict(const double *input, const double *heights,
                              int count, double spacing, double *output) {
    if (!input || !heights || !output || count < 3 || count > 4097 || spacing <= 0) return 2;
    try {
        std::vector<double> pfl(static_cast<size_t>(count) + 2);
        pfl[0] = count - 1; pfl[1] = spacing;
        for (int i = 0; i < count; ++i) {
            if (!std::isfinite(heights[i])) return 2;
            pfl[static_cast<size_t>(i) + 2] = heights[i];
        }
        double loss = 0; long warnings = 0; IntermediateValues values{};
        int status = ITM_P2P_CR_Ex(input[1], input[2], pfl.data(), static_cast<int>(input[3]),
            input[4], input[0], static_cast<int>(input[5]), input[6], input[7],
            static_cast<int>(input[13]), input[8], input[9], &loss, &warnings, &values);
        if ((status != SUCCESS && status != SUCCESS_WITH_WARNINGS) || !std::isfinite(loss)) return status;
        output[0] = loss;
        output[1] = 10 * std::log10(input[10] * 1000) + input[11] + input[12] - loss;
        output[2] = values.delta_h__meter;
        output[3] = values.d__km;
        output[4] = static_cast<double>(warnings);
        output[5] = values.mode;
        return status;
    } catch (...) { return 2; }
}
