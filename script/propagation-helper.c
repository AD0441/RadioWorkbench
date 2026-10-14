// Local stdin/stdout wrapper for the ITU-R Study Group 3 P.533/P.372 implementation.
// All coordinates and power inputs stay in this owned process. No network or radio control.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "P533.h"

static void number(double value) {
    if (isfinite(value)) printf("%.8f", value); else printf("null");
}
int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) { puts("RadioWorkbench P.533 14.2 / P.372 14.3 wrapper 1"); return 0; }
    if (argc != 2 || strlen(argv[1]) > 200) { fputs("Expected data directory (<201 bytes)\n", stderr); return 2; }
    char data[256]; snprintf(data, sizeof(data), "%s/", argv[1]);
    struct PathData path = {0};
    int month, ssn, noise;
    double txlat, txlon, power, bandwidth, required, txgain, rxgain;
    if (scanf("%d %d %d %lf %lf %lf %lf %lf %lf %lf %d", &path.year, &month, &ssn, &txlat, &txlon, &power, &bandwidth, &required, &txgain, &rxgain, &noise) != 11) return 2;
    if (path.year < 1900 || path.year > 2100 || month < 1 || month > 12 || ssn < 1 || ssn > 311 || noise < 0 || noise > 3 ||
        !isfinite(txlat) || fabs(txlat) > 90 || !isfinite(txlon) || fabs(txlon) > 180 ||
        !isfinite(power) || power < 1 || power > 1e6 || !isfinite(bandwidth) || bandwidth < 1 || bandwidth > 1e5 ||
        !isfinite(required) || required < -30 || required > 100 || !isfinite(txgain) || fabs(txgain) > 40 || !isfinite(rxgain) || fabs(rxgain) > 40) return 2;
    path.month = month - 1; path.SSN = ssn; path.Modulation = 0; path.SorL = 0;
    path.L_tx.lat = txlat * M_PI / 180; path.L_tx.lng = txlon * M_PI / 180;
    path.txpower = 10 * log10(power / 1000); path.BW = bandwidth; path.SNRr = required;
    path.SNRXXp = 50; path.SIRr = 0;
    if (AllocatePathMemory(&path) != RTN_ALLOCATEP533OK) return 3;
    IsotropicPattern(&path.A_tx, txgain, 1); IsotropicPattern(&path.A_rx, rxgain, 1);
    if (ReadIonParametersBin(path.month, path.foF2, path.M3kF2, data, 1) != RTN_READIONPARAOK ||
        ReadP1239(&path, data) != RTN_READP1239OK || ReadFamDud(&path.noiseP, data, path.month) != RTN_READFAMDUDOK) return 3;
    path.noiseP.ManMadeNoise = noise;
    int index, hour, count = 0; double rxlat, rxlon, frequency;
    while (scanf("%d %d %lf %lf %lf", &index, &hour, &rxlat, &rxlon, &frequency) == 5) {
        if (++count > 600 || index < 0 || hour < 0 || hour > 23 || !isfinite(rxlat) || fabs(rxlat) > 90 ||
            !isfinite(rxlon) || fabs(rxlon) > 180 || !isfinite(frequency) || frequency < 1.6 || frequency > 30) return 2;
        path.hour = hour; path.frequency = frequency;
        path.L_rx.lat = rxlat * M_PI / 180; path.L_rx.lng = rxlon * M_PI / 180;
        int status = P533(&path);
        if (status != RTN_P533OK) { fprintf(stderr, "P533 error %d\n", status); return 4; }
        printf("{\"id\":%d,\"hour\":%d,\"frequencyMHz\":%.6f,\"distanceKm\":", index, hour, frequency); number(path.distance);
        printf(",\"snrDB\":"); number(path.SNR);
        printf(",\"reliability\":"); number(path.BCR);
        printf(",\"muf50MHz\":"); if (path.distance <= 9000 && path.MUF50 > 0) number(path.MUF50); else printf("null");
        printf(",\"receivedDBm\":"); number(path.Pr + 30);
        printf(",\"noiseFactorDB\":"); number(path.noiseP.FamT);
        printf(",\"atmosphericNoiseDB\":"); number(path.noiseP.FaA);
        printf(",\"manMadeNoiseDB\":"); number(path.noiseP.FaM);
        printf(",\"galacticNoiseDB\":"); number(path.noiseP.FaG);
        printf("}\n");
    }
    FreePathMemory(&path);
    return count == 0 ? 2 : 0;
}
