#include <stdio.h>

// Birthday Paradox - Hash Collision Probability
float birthday_paradox(int n, int days) {
    float x = 1.0;
    for(int i = 1; i < n; i++){
        x *= (float)(days - i) / days;
    }
    return 1.0 - x;
}

int main() {
    // Calculate collision probability for different scenarios
    printf("Birthday Paradox - Hash Collision Probabilities:\n\n");

    for(int j = 1; j < 180; j++){
    float prob = birthday_paradox(j, 365);
    printf("%d people, 365 days: %.1f%% collision chance\n", j, prob * 100);
    printf("%d people, 365 days: not collision chance %f%%\n", j, (1-prob) * 100);
    }

    
    return 0;
}