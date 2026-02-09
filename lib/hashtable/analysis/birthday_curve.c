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

// Approximate Birthday Paradox formula
double birthday_approximation(int n, int days) {
    return 1.0 - exp(-(double)(n * (n - 1)) / (2.0 * days));
}

// Poisson approximation
double poisson_approximation(int n, int days) {
    double lambda = (double)(n * (n - 1)) / (2.0 * days);
    return 1.0 - exp(-lambda);
}

int main() {
    printf("Birthday Paradox - Curve Analysis\n");
    printf("================================\n\n");
    
    printf("n,Exact,Approximation,Poisson,Difference\n");
    
    for(int n = 1; n <= 100; n++){
        double exact = birthday_paradox(n, 365);
        double approx = birthday_approximation(n, 365);
        double poisson = poisson_approximation(n, 365);
        double diff = fabs(exact - approx);
        
        printf("%d,%.6f,%.6f,%.6f,%.6f\n", n, exact, approx, poisson, diff);
    }
    
    printf("\nBest fit function analysis:\n");
    printf("1. Exact formula: P(n) = 1 - ∏(i=1 to n-1) (365-i)/365\n");
    printf("2. Approximation: P(n) ≈ 1 - e^(-n(n-1)/(2*365))\n");
    printf("3. Poisson: P(n) ≈ 1 - e^(-λ) where λ = n(n-1)/(2*365)\n");
    
    return 0;
}
