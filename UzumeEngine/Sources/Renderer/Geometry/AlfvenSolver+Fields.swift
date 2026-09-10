// AlfvenSolver+Fields — the solver's texture set, split out at the 400-line ceiling.
//
// Purely a declaration of what the scheme needs to hold: the complex scratch it transforms
// through, the four derivative fields, the RK2 stage slopes, and the seam-bloom chain. No
// behaviour, so it is the cheapest thing to move out of the solver proper.

import Foundation
import Metal

extension AlfvenSolver {

    /// Working textures. Grouped so they are non-optional and allocated together —
    /// implicitly-unwrapped optionals are a lint error and, here, would also hide an
    /// allocation failure until first use.
    struct Fields {
        let scratchA: MTLTexture      // spectra / intermediate complex fields
        let scratchB: MTLTexture
        let scratchC: MTLTexture      // inverse staging, keeps fields.scratchB intact
        let gradPhi: MTLTexture
        let gradOmega: MTLTexture
        let gradPsi: MTLTexture
        let gradJ: MTLTexture
        let nonlinear: MTLTexture
        /// The spectrally filtered state — what each step advances FROM.
        let filtered: MTLTexture
        /// J = lap(psi), computed spectrally. What the fragment colours.
        let jField: MTLTexture
        /// RK2 stage slopes: k1 held across the second RHS evaluation, and the
        /// half-step base E(w + 0.5*dt*k1) it is combined with.
        let k1: MTLTexture
        let rk: MTLTexture
        /// Seam-bloom chain: the thresholded core, a ping for the separable blur, and the
        /// two blurred levels film.py adds back (sigma 2 and sigma 7).
        let bloomCore: MTLTexture
        let bloomTmp: MTLTexture
        let bloomNear: MTLTexture
        let bloomFar: MTLTexture
    }
}
