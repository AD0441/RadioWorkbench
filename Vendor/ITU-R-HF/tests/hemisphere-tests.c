// Focused regression checks for the locally corrected P.533 implementation.
// Normative references and original/fixed numerical evidence: LOCAL-CHANGES.md.
// Link to the built libp533; no radio, network, or UI access is performed.
#include <stdio.h>
#include <math.h>
#include "Common.h"
#include "P533.h"

static int failures = 0, checks = 0;
static void near(const char *name, double actual, double expected, double tolerance) {
    checks++;
    if (!isfinite(actual) || fabs(actual - expected) > tolerance) {
        fprintf(stderr, "%s: got %.12f, expected %.12f\n", name, actual, expected);
        failures++;
    }
}

static struct ControlPt point(double latitude, double longitude) {
    struct ControlPt cp = {0};
    cp.L.lat = latitude * D2R; cp.L.lng = longitude * D2R;
    return cp;
}

// Independent evaluation of P.1239-3 eqs (12)..(18) for a controlled
// night-time geometry: solar declination 0, zenith 110 degrees, h=1 hour.
// Normal night must use max(17d,17e); polar winter must use only (17e).
static double expectedNightfoE(double latitude, int polarWinter) {
    const double lat = latitude * D2R, phi = 63.7 + .728 * 75 + .00089 * 75 * 75;
    const double a = 1 + .0094 * (phi - 66);
    const double m = fabs(latitude) < 32 ? -1.93 + 1.92 * cos(lat) : .11 - .49 * cos(lat);
    const double b = pow(cos(fmin(fabs(lat), 80 * D2R)), m);
    const double c = fabs(latitude) < 32 ? 23 + 116 * cos(lat) : 92 + 35 * cos(lat);
    const double p = fabs(latitude) <= 12 ? 1.31 : 1.20;
    const double polar = pow(.072, p) * exp(25.2 - .28 * 110);
    const double afterSunset = pow(.072, p) * exp(-1.4);
    const double d = polarWinter ? polar : fmax(afterSunset, polar);
    return fmax(pow(a * b * c * d, .25), pow(.004 * pow(1 + .021 * phi, 2), .25));
}

static void nightCase(const char *name, double latitude, int month, int polarWinter) {
    struct ControlPt cp = point(latitude, 0);
    cp.Sun.sza = 110 * D2R; cp.Sun.decl = 0;
    cp.Sun.lsr = 6; cp.Sun.lss = 20;
    FindfoE(&cp, month, 20, 75); // existing P.533 hour-index convention gives h=1.
    near(name, cp.foE, expectedNightfoE(latitude, polarWinter), 1e-8);
}

static struct PathData reliabilityPath(void) {
    struct PathData path = {0};
    path.distance = 3000; path.frequency = 5; path.BMUF = 10;
    path.BW = 1000; path.Pr = -170; path.SNRr = 5;
    path.Modulation = ANALOG; path.SNRXXp = 50;
    for (int i = 0; i < 5; ++i) path.CP[i] = point(0, -68.2);
    return path;
}

static void validateSolarMinimum(void) {
    // ValidatePath checks that tables/patterns are present but never reads them.
    struct PathData path = {0};
    path.year = 2026; path.frequency = 7.1; path.BW = 2400;
    path.txpower = -10; path.SNRr = 10; path.SNRXXp = 50;
    path.foF2 = (void *)1; path.M3kF2 = (void *)1; path.foF2var = (void *)1;
    path.noiseP.dud = (void *)1; path.noiseP.fam = (void *)1;
    path.A_tx.pattern = (void *)1; path.A_rx.pattern = (void *)1;
    for (int ssn = -1; ssn <= 1; ++ssn) {
        path.SSN = ssn;
        near(ssn == 0 ? "R12 zero valid" : "R12 range boundary", ValidatePath(&path),
             ssn < 0 ? RTN_ERRSSN : RTN_VALIDDATAOK, 0);
    }
    path.SSN = 311; near("R12 upper guard retained", ValidatePath(&path), RTN_VALIDDATAOK, 0);
    path.SSN = 312; near("R12 above upper guard rejected", ValidatePath(&path), RTN_ERRSSN, 0);
}

int main(void) {
    nightCase("Equatorial ordinary June night", 0, JUN, 0);
    nightCase("Midlatitude southern June night", -33.45, JUN, 0);
    nightCase("Midlatitude northern June night", 50, JUN, 0);
    nightCase("Northern polar January night retained", 78, JAN, 1);
    nightCase("Southern polar June night retained", -78, JUN, 1);

    struct ControlPt santiago = point(-33.45, -70.67);
    SolarParameters(&santiago, JUN, 11);
    FindfoE(&santiago, JUN, 11, 75);
    near("Santiago June 11UTC numeric regression", santiago.foE, 1.75548953, 1e-7);

    // P.842-5 Table 2: f/BMUF<=.8 gives upper day-to-day deciles
    // 6dB below |geomagnetic latitude|60 and 9dB above it.
    const double snr = -170 - 10 * log10(3) - 10 * log10(1000) + 204;
    const double lowBCR = 80 / (1 + (5 - snr) / sqrt(6 * 6 + 5 * 5)) - 30;
    const double highBCR = 80 / (1 + (5 - snr) / sqrt(9 * 9 + 5 * 5)) - 30;
    struct PathData low = reliabilityPath();
    CircuitReliability(&low);
    near("Equatorial variability table retained", low.BCR, lowBCR, 1e-8);
    const int controlPoints[] = {MP, T1k, R1k};
    for (int i = 0; i < 3; ++i) {
        struct PathData north = reliabilityPath(), south = reliabilityPath();
        north.CP[controlPoints[i]] = point(60, -68.2);
        south.CP[controlPoints[i]] = point(-60, 111.8);
        CircuitReliability(&north); CircuitReliability(&south);
        near("Northern high-geomagnetic variability", north.BCR, highBCR, 1e-8);
        near("Southern high-geomagnetic variability", south.BCR, highBCR, 1e-8);
        near("Northern/southern variability symmetry", north.BCR, south.BCR, 1e-8);
    }
    validateSolarMinimum();
    printf("{\"checks\":%d,\"failures\":%d,\"equatorialBCR\":%.8f,\"polarBCR\":%.8f,\"santiagoJuneFoEMHz\":%.8f}\n",
           checks, failures, lowBCR, highBCR, santiago.foE);
    return failures ? 1 : 0;
}
