#!/usr/bin/env python3
import numpy as np
import matplotlib.pyplot as plt
from scipy.optimize import curve_fit
import pandas as pd

# Read the data
data = pd.read_csv('birthday_data.csv', names=['n', 'exact', 'approx', 'poisson', 'diff'])

# Extract data
n = data['n'].values
exact = data['exact'].values
approx = data['approx'].values

# Define different fit functions
def exponential_fit(x, a, b, c):
    """Exponential fit: y = a * (1 - exp(-b * x^c))"""
    return a * (1 - np.exp(-b * np.power(x, c)))

def logistic_fit(x, a, b, c):
    """Logistic fit: y = a / (1 + exp(-b * (x - c)))"""
    return a / (1 + np.exp(-b * (x - c)))

def power_fit(x, a, b, c):
    """Power fit: y = a * x^b + c"""
    return a * np.power(x, b) + c

def polynomial_fit(x, a, b, c, d):
    """Polynomial fit: y = a*x^3 + b*x^2 + c*x + d"""
    return a*x**3 + b*x**2 + c*x + d

# Fit the functions
try:
    popt_exp, _ = curve_fit(exponential_fit, n, exact, maxfev=10000)
    popt_log, _ = curve_fit(logistic_fit, n, exact, maxfev=10000)
    popt_pow, _ = curve_fit(power_fit, n, exact, maxfev=10000)
    popt_poly, _ = curve_fit(polynomial_fit, n, exact, maxfev=10000)
    
    # Calculate R-squared for each fit
    def r_squared(y_true, y_pred):
        ss_res = np.sum((y_true - y_pred) ** 2)
        ss_tot = np.sum((y_true - np.mean(y_true)) ** 2)
        return 1 - (ss_res / ss_tot)
    
    # Predictions
    n_smooth = np.linspace(1, 100, 1000)
    y_exp = exponential_fit(n_smooth, *popt_exp)
    y_log = logistic_fit(n_smooth, *popt_log)
    y_pow = power_fit(n_smooth, *popt_pow)
    y_poly = polynomial_fit(n_smooth, *popt_poly)
    
    # R-squared values
    r2_exp = r_squared(exact, exponential_fit(n, *popt_exp))
    r2_log = r_squared(exact, logistic_fit(n, *popt_log))
    r2_pow = r_squared(exact, power_fit(n, *popt_pow))
    r2_poly = r_squared(exact, polynomial_fit(n, *popt_poly))
    
    print("Best Fit Functions for Birthday Paradox:")
    print("=======================================")
    print(f"Exponential: R² = {r2_exp:.6f}")
    print(f"Logistic:    R² = {r2_log:.6f}")
    print(f"Power:       R² = {r2_pow:.6f}")
    print(f"Polynomial:  R² = {r2_poly:.6f}")
    
    # Find best fit
    fits = [("Exponential", r2_exp), ("Logistic", r2_log), ("Power", r2_pow), ("Polynomial", r2_poly)]
    best_fit = max(fits, key=lambda x: x[1])
    print(f"\nBest fit: {best_fit[0]} (R² = {best_fit[1]:.6f})")
    
    # Plot
    plt.figure(figsize=(12, 8))
    plt.plot(n, exact, 'bo', label='Exact Birthday Paradox', markersize=4)
    plt.plot(n_smooth, y_exp, 'r-', label=f'Exponential (R²={r2_exp:.4f})', alpha=0.7)
    plt.plot(n_smooth, y_log, 'g-', label=f'Logistic (R²={r2_log:.4f})', alpha=0.7)
    plt.plot(n_smooth, y_pow, 'm-', label=f'Power (R²={r2_pow:.4f})', alpha=0.7)
    plt.plot(n_smooth, y_poly, 'c-', label=f'Polynomial (R²={r2_poly:.4f})', alpha=0.7)
    
    plt.xlabel('Number of People (n)')
    plt.ylabel('Collision Probability')
    plt.title('Birthday Paradox - Best Fit Functions')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.xlim(0, 100)
    plt.ylim(0, 1)
    
    # Highlight 50% threshold
    plt.axhline(y=0.5, color='red', linestyle='--', alpha=0.5, label='50% threshold')
    plt.axvline(x=23, color='red', linestyle='--', alpha=0.5, label='n=23')
    
    plt.tight_layout()
    plt.savefig('birthday_curve.png', dpi=300, bbox_inches='tight')
    plt.show()
    
    # Print function parameters
    print(f"\nExponential fit parameters: a={popt_exp[0]:.6f}, b={popt_exp[1]:.6f}, c={popt_exp[2]:.6f}")
    print(f"Logistic fit parameters: a={popt_log[0]:.6f}, b={popt_log[1]:.6f}, c={popt_log[2]:.6f}")
    print(f"Power fit parameters: a={popt_pow[0]:.6f}, b={popt_pow[1]:.6f}, c={popt_pow[2]:.6f}")
    print(f"Polynomial fit parameters: a={popt_poly[0]:.6f}, b={popt_poly[1]:.6f}, c={popt_poly[2]:.6f}, d={popt_poly[3]:.6f}")
    
except Exception as e:
    print(f"Error in curve fitting: {e}")
    print("Make sure you have the required packages: pip install numpy matplotlib scipy pandas")
