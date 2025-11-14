//
//  DepthBiasRegression.swift
//  SUPERWAAGE
//
//  Linear and polynomial regression for depth bias correction
//  Compensates for LiDAR/depth measurement errors at different distances
//

import Foundation
import Accelerate

/// Performs regression analysis for depth bias correction
class DepthBiasRegression {

    /// Perform linear regression: y = a + b*x
    /// - Parameters:
    ///   - x: Independent variable (distances)
    ///   - y: Dependent variable (errors/biases)
    /// - Returns: Coefficients [a, b] and MSE
    func linearRegression(x: [Double], y: [Double]) -> (coefficients: [Double], mse: Double)? {
        guard x.count == y.count, x.count >= 2 else {
            print("❌ Linear regression failed: not enough data points (\(x.count))")
            return nil
        }

        // ✅ Validate input data
        guard x.allSatisfy({ $0.isFinite }) && y.allSatisfy({ $0.isFinite }) else {
            print("❌ Linear regression failed: non-finite values in input")
            return nil
        }

        let n = Double(x.count)

        // Calculate means
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        guard meanX.isFinite && meanY.isFinite else {
            print("❌ Linear regression failed: non-finite mean values")
            return nil
        }

        // Calculate slope (b)
        var numerator = 0.0
        var denominator = 0.0

        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            numerator += dx * dy
            denominator += dx * dx
        }

        guard denominator != 0 && denominator.isFinite else {
            print("❌ Linear regression failed: denominator is zero or non-finite")
            return nil
        }

        let b = numerator / denominator
        let a = meanY - b * meanX

        guard a.isFinite && b.isFinite else {
            print("❌ Linear regression failed: non-finite coefficients")
            return nil
        }

        // Calculate MSE
        let mse = calculateMSE(x: x, y: y, coefficients: [a, b])

        guard mse.isFinite else {
            print("❌ Linear regression failed: non-finite MSE")
            return nil
        }

        print("✅ Linear regression successful: a=\(a), b=\(b), mse=\(mse)")
        return ([a, b], mse)
    }

    /// Perform polynomial regression: y = a + b*x + c*x²
    /// - Parameters:
    ///   - x: Independent variable (distances)
    ///   - y: Dependent variable (errors/biases)
    ///   - degree: Polynomial degree (2 for quadratic)
    /// - Returns: Coefficients [a, b, c, ...] and MSE
    func polynomialRegression(x: [Double], y: [Double], degree: Int = 2) -> (coefficients: [Double], mse: Double)? {
        guard x.count == y.count, x.count >= degree + 1 else { return nil }

        let n = x.count

        // Build design matrix X (Vandermonde matrix)
        var designMatrix: [Double] = []
        for xi in x {
            for power in 0...degree {
                designMatrix.append(pow(xi, Double(power)))
            }
        }

        // Solve using least squares: (X^T X)^-1 X^T y
        let coefficients = leastSquaresSolve(
            designMatrix: designMatrix,
            observations: y,
            rows: n,
            cols: degree + 1
        )

        guard let coeffs = coefficients else { return nil }

        // Calculate MSE
        let mse = calculateMSE(x: x, y: y, coefficients: coeffs)

        return (coeffs, mse)
    }

    // MARK: - Private Helpers

    /// Least squares solver using Accelerate framework
    private func leastSquaresSolve(designMatrix: [Double], observations: [Double], rows: Int, cols: Int) -> [Double]? {
        var A = designMatrix
        var b = observations
        var m = __CLPK_integer(rows)
        var n = __CLPK_integer(cols)
        var nrhs = __CLPK_integer(1)
        var lda = m
        var ldb = max(m, n)
        var wkopt: Double = 0
        var lwork = __CLPK_integer(-1)
        var info: __CLPK_integer = 0

        // Workspace query
        dgels_(
            UnsafeMutablePointer(mutating: ("N" as NSString).utf8String),
            &m, &n, &nrhs,
            &A, &lda,
            &b, &ldb,
            &wkopt, &lwork,
            &info
        )

        guard info == 0 else { return nil }

        lwork = __CLPK_integer(wkopt)
        var work = [Double](repeating: 0, count: Int(lwork))

        // Solve
        dgels_(
            UnsafeMutablePointer(mutating: ("N" as NSString).utf8String),
            &m, &n, &nrhs,
            &A, &lda,
            &b, &ldb,
            &work, &lwork,
            &info
        )

        guard info == 0 else { return nil }

        // Extract coefficients
        return Array(b.prefix(cols))
    }

    /// Calculate Mean Squared Error
    private func calculateMSE(x: [Double], y: [Double], coefficients: [Double]) -> Double {
        var sumSquaredError = 0.0

        for i in 0..<x.count {
            let predicted = predict(x: x[i], coefficients: coefficients)
            let error = y[i] - predicted
            sumSquaredError += error * error
        }

        return sumSquaredError / Double(x.count)
    }

    /// Predict y value using polynomial coefficients
    private func predict(x: Double, coefficients: [Double]) -> Double {
        var result = 0.0
        for (power, coeff) in coefficients.enumerated() {
            result += coeff * pow(x, Double(power))
        }
        return result
    }
}
