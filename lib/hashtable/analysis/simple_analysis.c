#include <stdio.h>
#include <math.h>

// Birthday Paradox - Hash Collision Probability
double birthday_paradox(int n, int days) {
    double x = 1.0;
    for(int i = 1; i < n; i++){
        x *= (double)(days - i) / days;
    }
    return 1.0 - x;
}

// Different approximation functions
double exponential_approx(int n, int days) {
    return 1.0 - exp(-(double)(n * (n - 1)) / (2.0 * days));
}

double logistic_approx(int n, int days) {
    double x = (double)n / 23.0;  // Scale around n=23
    return 1.0 / (1.0 + exp(-2.0 * (x - 1.0)));
}

double power_approx(int n, int days) {
    return pow((double)n / 23.0, 2.0) * 0.5;
}

double polynomial_approx(int n, int days) {
    double x = (double)n / 100.0;  // Normalize to [0,1]
    return 0.1 * x + 0.9 * x * x * x;  // Cubic polynomial
}

int main() {
    printf("Birthday Paradox - Function Analysis\n");
    printf("===================================\n\n");
    
    printf("n,Exact,Exponential,Logistic,Power,Polynomial\n");
    
    double total_error_exp = 0, total_error_log = 0, total_error_pow = 0, total_error_poly = 0;
    int count = 0;
    
    for(int n = 1; n <= 100; n++){
        double exact = birthday_paradox(n, 365);
        double exp_approx = exponential_approx(n, 365);
        double log_approx = logistic_approx(n, 365);
        double pow_approx = power_approx(n, 365);
        double poly_approx = polynomial_approx(n, 365);
        
        // Calculate errors
        double error_exp = fabs(exact - exp_approx);
        double error_log = fabs(exact - log_approx);
        double error_pow = fabs(exact - pow_approx);
        double error_poly = fabs(exact - poly_approx);
        
        total_error_exp += error_exp;
        total_error_log += error_log;
        total_error_pow += error_pow;
        total_error_poly += error_poly;
        count++;
        
        printf("%d,%.6f,%.6f,%.6f,%.6f,%.6f\n", 
               n, exact, exp_approx, log_approx, pow_approx, poly_approx);
    }
    
    printf("\nAverage Error Analysis:\n");
    printf("======================\n");
    printf("Exponential: %.6f\n", total_error_exp / count);
    printf("Logistic:    %.6f\n", total_error_log / count);
    printf("Power:       %.6f\n", total_error_pow / count);
    printf("Polynomial:  %.6f\n", total_error_poly / count);
    
    printf("\nBest Fit Functions:\n");
    printf("==================\n");
    printf("1. Exponential: P(n) ≈ 1 - e^(-n(n-1)/(2*365))\n");
    printf("   - Best for: Mathematical accuracy\n");
    printf("   - Error: %.6f\n", total_error_exp / count);
    
    printf("2. Logistic: P(n) ≈ 1/(1 + e^(-2*(n/23 - 1)))\n");
    printf("   - Best for: S-curve behavior\n");
    printf("   - Error: %.6f\n", total_error_log / count);
    
    printf("3. Power: P(n) ≈ (n/23)^2 * 0.5\n");
    printf("   - Best for: Simple approximation\n");
    printf("   - Error: %.6f\n", total_error_pow / count);
    
    printf("4. Polynomial: P(n) ≈ 0.1*(n/100) + 0.9*(n/100)^3\n");
    printf("   - Best for: Smooth curve fitting\n");
    printf("   - Error: %.6f\n", total_error_poly / count);
    
    // Find best fit
    double errors[] = {total_error_exp/count, total_error_log/count, 
                      total_error_pow/count, total_error_poly/count};
    char* names[] = {"Exponential", "Logistic", "Power", "Polynomial"};
    
    int best = 0;
    for(int i = 1; i < 4; i++) {
        if(errors[i] < errors[best]) {
            best = i;
        }
    }
    
    printf("\nBEST FIT: %s (Average Error: %.6f)\n", names[best], errors[best]);
    
    return 0;
}
