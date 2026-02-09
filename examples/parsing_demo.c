/* Parsing Demonstration - How "2 + 3 * 4" is parsed
 * 
 * Input tokens: [NUMBER:2] [PLUS] [NUMBER:3] [MULTIPLY] [NUMBER:4]
 * 
 * Call stack trace:
 * 1. parse_additive_expression()
 *    2. parse_multiplicative_expression()  // Gets 2
 *       3. parse_primary_expression()      // Returns NUMBER:2
 *    4. Sees PLUS, continues loop
 *    5. parse_multiplicative_expression()  // Gets 3*4
 *       6. parse_primary_expression()      // Returns NUMBER:3
 *       7. Sees MULTIPLY, continues loop
 *       8. parse_primary_expression()      // Returns NUMBER:4
 *       9. Returns BINARY_OP(MULTIPLY, 3, 4)
 *    10. Returns BINARY_OP(PLUS, 2, (3*4))
 * 
 * Final AST:
 *       PLUS
 *      /    \
 *     2    MULTIPLY
 *          /      \
 *         3        4
 * 
 * This correctly represents: 2 + (3 * 4) = 14
 * Instead of wrong: (2 + 3) * 4 = 20
 */

#include <stdio.h>

void demonstrate_parsing() {
    printf("Parsing '2 + 3 * 4':\n");
    printf("1. parse_additive_expression() called\n");
    printf("2.   parse_multiplicative_expression() -> gets '2'\n");
    printf("3.   Sees '+', continues\n");
    printf("4.   parse_multiplicative_expression() -> gets '3 * 4'\n");
    printf("5.     parse_primary_expression() -> gets '3'\n");
    printf("6.     Sees '*', continues\n");
    printf("7.     parse_primary_expression() -> gets '4'\n");
    printf("8.     Returns BINARY_OP(*, 3, 4)\n");
    printf("9.   Returns BINARY_OP(+, 2, (3*4))\n");
    printf("\nResult: 2 + (3 * 4) = 14 ✓\n");
}

int main() {
    demonstrate_parsing();
    return 0;
}

