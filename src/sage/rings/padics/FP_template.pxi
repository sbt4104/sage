"""
Floating point template for complete discrete valuation rings.

In order to use this template you need to write a linkage file and
gluing file.  For an example see mpz_linkage.pxi (linkage file) and
padic_floating_point_element.pyx (gluing file).

The linkage file implements a common API that is then used in the
class FPElement defined here.  See sage/libs/linkages/padics/API.pxi
for the functions needed.

The gluing file does the following:

- ctypedef's celement to be the appropriate type (e.g. mpz_t)
- includes the linkage file
- includes this template
- defines a concrete class inheriting from FPElement, and implements
  any desired extra methods

AUTHORS:

- David Roe (2016-03-21) -- initial version
"""

#*****************************************************************************
#       Copyright (C) 2007-2016 David Roe <roed.math@gmail.com>
#                               William Stein <wstein@gmail.com>
#
#  Distributed under the terms of the GNU General Public License (GPL)
#  as published by the Free Software Foundation; either version 2 of
#  the License, or (at your option) any later version.
#
#                  http://www.gnu.org/licenses/
#*****************************************************************************

from sage.ext.stdsage cimport PY_NEW
include "padic_template_element.pxi"
from cpython.int cimport *

from sage.structure.element cimport Element
from sage.rings.padics.common_conversion cimport comb_prec, _process_args_and_kwds
from sage.rings.integer_ring import ZZ
from sage.rings.rational_field import QQ
from sage.categories.sets_cat import Sets
from sage.categories.sets_with_partial_maps import SetsWithPartialMaps
from sage.categories.homset import Hom

cdef inline bint overunderflow(long* ordp, celement unit, PowComputer_ prime_pow):
    """
    Check for over and underflow.  If detected, sets ordp and unit
    appropriately, and returns True.  If not, returns False.
    """
    if ordp[0] >= maxordp:
        ordp[0] = maxordp
        csetzero(unit, prime_pow)
    elif ordp[0] <= minusmaxordp:
        ordp[0] = minusmaxordp
        csetone(unit, prime_pow)
    else:
        return False
    return True

cdef inline bint overunderflow_mpz(long* ordp, mpz_t ordp_mpz, celement unit, PowComputer_ prime_pow):
    """
    Check for over and underflow with an mpz_t ordp.  If detected, sets ordp and unit
    appropriately, and returns True.  If not, returns False.
    """
    if mpz_fits_slong_p(ordp_mpz) == 0 or mpz_cmp_si(ordp_mpz, maxordp) >= 0 or mpz_cmp_si(ordp_mpz, minusmaxordp) <= 0:
        if mpz_sgn(ordp_mpz) > 0:
            ordp[0] = maxordp
            csetzero(unit, prime_pow)
        else:
            ordp[0] = minusmaxordp
            csetone(unit, prime_pow)
        return True
    return False

cdef inline bint very_pos_val(long ordp):
    return ordp >= maxordp

cdef inline bint very_neg_val(long ordp):
    return ordp <= minusmaxordp

cdef inline bint huge_val(long ordp):
    return very_pos_val(ordp) or very_neg_val(ordp)

cdef class FPElement(pAdicTemplateElement):
    cdef int _set(self, x, long val, long xprec, absprec, relprec) except -1:
        """
        Sets the value of this element from given defining data.

        This function is intended for use in conversion, and should
        not be called on an element created with :meth:`_new_c`.

        INPUT:

        - ``x`` -- data defining a `p`-adic element: int, long,
          Integer, Rational, other `p`-adic element...

        - ``val`` -- the valuation of the resulting element (unused;
          for compatibility with other `p`-adic precision modes)

        - ``xprec -- an inherent precision of ``x`` (unused; for
          compatibility with other `p`-adic precision modes)

        - ``absprec`` -- an absolute precision cap for this element
          (unused; for compatibility with other `p`-adic precision
          modes)

        - ``relprec`` -- a relative precision cap for this element
          (unused; for compatibility with other `p`-adic precision
          modes)

        TESTS::

            sage: R = ZpFP(5)
            sage: a = R(17,5); a #indirect doctest
            2 + 3*5
            sage: R(15) #indirect doctest
            3*5

            sage: R = ZpFP(5,5)
            sage: a = R(25/9); a #indirect doctest
            4*5^2 + 2*5^3 + 5^5 + 2*5^6
            sage: R(ZpCR(5)(25/9)) == a
            True
            sage: R(5) - R(5)
            0
        """
        cconstruct(self.unit, self.prime_pow)
        if very_pos_val(val):
            self._set_exact_zero()
        elif very_neg_val(val):
            self._set_infinity()
        else:
            self.ordp = val
            if isinstance(x,FPElement) and x.parent() is self.parent():
                ccopy(self.unit, (<FPElement>x).unit, self.prime_pow)
            else:
                cconv(self.unit, x, self.prime_pow.prec_cap, val, self.prime_pow)

    cdef int _set_exact_zero(self) except -1:
        """
        Sets this element to zero.

        TESTS::

            sage: R = Zp(5); R(0) #indirect doctest
            0
        """
        csetzero(self.unit, self.prime_pow)
        self.ordp = maxordp

    cdef int _set_infinity(self) except -1:
        """
        Sets this element to zero.

        TESTS::

            sage: R = Zp(5); R(0) #indirect doctest
            0
        """
        csetone(self.unit, self.prime_pow)
        self.ordp = minusmaxordp

    cdef FPElement _new_c(self):
        """
        Creates a new element with the same basic info.

        TESTS::

            sage: R = ZpFP(5); R(6) * R(7) #indirect doctest
            2 + 3*5 + 5^2
        """
        cdef type t = type(self)
        cdef FPElement ans = t.__new__(t)
        ans._parent = self._parent
        ans.prime_pow = self.prime_pow
        cconstruct(ans.unit, ans.prime_pow)
        return ans

    cdef int check_preccap(self) except -1:
        """
        Check that the precision of this element does not exceed the
        precision cap. Does nothing for floating point elements.

        TESTS::

            sage: ZpFP(5)(1).lift_to_precision(30) # indirect doctest
            1
        """
        pass

    def __copy__(self):
        """
        Return a copy of this element.

        EXAMPLES::

            sage: a = ZpFP(5,6)(17); b = copy(a)
            sage: a == b
            True
            sage: a is b
            False
        """
        cdef FPElement ans = self._new_c()
        ans.ordp = self.ordp
        ccopy(ans.unit, self.unit, ans.prime_pow)
        return ans

    cdef int _normalize(self) except -1:
        """
        Normalizes this element, so that ``self.ordp`` is correct.

        TESTS::

            sage: R = ZpFP(5)
            sage: R(6) + R(4) #indirect doctest
            2*5
        """
        cdef long diff
        cdef bint is_zero
        if very_pos_val(self.ordp):
            self._set_exact_zero()
        elif very_neg_val(self.ordp):
            self._set_infinity()
        else:
            is_zero = creduce(self.unit, self.unit, self.prime_pow.prec_cap, self.prime_pow)
            if is_zero:
                self.ordp = maxordp
            else:
                diff = cremove(self.unit, self.unit, self.prime_pow.prec_cap, self.prime_pow)
                self.ordp += diff
                if very_pos_val(self.ordp):
                    self._set_exact_zero()

    def __dealloc__(self):
        """
        Deallocate the underlying data structure.

        TESTS::

            sage: R = ZpFP(5)
            sage: a = R(17)
            sage: del(a)
        """
        cdestruct(self.unit, self.prime_pow)

    def __reduce__(self):
        """
        Return a tuple of a function and data that can be used to unpickle this
        element.

        EXAMPLES::

            sage: a = ZpFP(5)(-3)
            sage: type(a)
            <type 'sage.rings.padics.padic_floating_point_element.pAdicFloatingPointElement'>
            sage: loads(dumps(a)) == a
            True
        """
        return unpickle_fpe_v2, (self.__class__, self.parent(), cpickle(self.unit, self.prime_pow), self.ordp)

#    def __richcmp__(self, right, int op):
#        """
#        Compare this element to ``right`` using the comparison operator ``op``.
#
#        TESTS::
#
#            sage: R = ZpFP(5)
#            sage: a = R(17)
#            sage: b = R(21)
#            sage: a == b
#            False
#            sage: a < b
#            True
#        """
#        return (<Element>self)._richcmp(right, op)

    cpdef _neg_(self):
        r"""
        Return the additive inverse of this element.

        EXAMPLES::

            sage: R = Zp(7, 4, 'floating-point', 'series')
            sage: -R(7) #indirect doctest
            6*7 + 6*7^2 + 6*7^3 + 6*7^4
        """
        cdef FPElement ans = self._new_c()
        ans.ordp = self.ordp
        if huge_val(self.ordp): # zero or infinity
            ccopy(ans.unit, self.unit, ans.prime_pow)
        else:
            cneg(ans.unit, self.unit, ans.prime_pow.prec_cap, ans.prime_pow)
            creduce_small(ans.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        return ans

    cpdef _add_(self, _right):
        r"""
        Return the sum of this element and ``_right``.

        EXAMPLES::

            sage: R = Zp(7, 4, 'floating-point', 'series')
            sage: x = R(1721); x
            6 + 5*7^3
            sage: y = R(1373); y
            1 + 4*7^3
            sage: x + y #indirect doctest
            7 + 2*7^3
        """
        cdef FPElement ans
        cdef FPElement right = _right
        cdef long tmpL
        if self.ordp == right.ordp:
            ans = self._new_c()
            ans.ordp = self.ordp
            if huge_val(ans.ordp):
                ccopy(ans.unit, self.unit, ans.prime_pow)
            else:
                cadd(ans.unit, self.unit, right.unit, ans.prime_pow.prec_cap, ans.prime_pow)
                ans._normalize() # safer than trying to leave unnormalized
        else:
            if self.ordp > right.ordp:
                # Addition is commutative, swap so self.ordp < right.ordp
                ans = right; right = self; self = ans
            tmpL = right.ordp - self.ordp
            if tmpL > self.prime_pow.prec_cap:
                return self
            ans = self._new_c()
            ans.ordp = self.ordp
            if huge_val(ans.ordp):
                ccopy(ans.unit, self.unit, ans.prime_pow)
            else:
                cshift(ans.unit, right.unit, tmpL, ans.prime_pow.prec_cap, ans.prime_pow, False)
                cadd(ans.unit, ans.unit, self.unit, ans.prime_pow.prec_cap, ans.prime_pow)
                creduce(ans.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        return ans

    cpdef _sub_(self, _right):
        r"""
        Return the difference of this element and ``_right``.

        EXAMPLES::

            sage: R = Zp(7, 4, 'floating-point', 'series')
            sage: x = R(1721); x
            6 + 5*7^3
            sage: y = R(1373); y
            1 + 4*7^3
            sage: x - y #indirect doctest
            5 + 7^3
        """
        cdef FPElement ans
        cdef FPElement right = _right
        cdef long tmpL
        if self.ordp == right.ordp:
            ans = self._new_c()
            ans.ordp = self.ordp
            if huge_val(ans.ordp):
                ccopy(ans.unit, self.unit, ans.prime_pow)
            else:
                csub(ans.unit, self.unit, right.unit, ans.prime_pow.prec_cap, ans.prime_pow)
                ans._normalize() # safer than trying to leave unnormalized
        elif self.ordp < right.ordp:
            tmpL = right.ordp - self.ordp
            if tmpL > self.prime_pow.prec_cap:
                return self
            ans = self._new_c()
            ans.ordp = self.ordp
            if huge_val(ans.ordp):
                ccopy(ans.unit, self.unit, ans.prime_pow)
            else:
                cshift(ans.unit, right.unit, tmpL, ans.prime_pow.prec_cap, ans.prime_pow, False)
                csub(ans.unit, self.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
                creduce(ans.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        else:
            tmpL = self.ordp - right.ordp
            if tmpL > self.prime_pow.prec_cap:
                return right._neg_()
            ans = self._new_c()
            ans.ordp = right.ordp
            if huge_val(ans.ordp):
                ccopy(ans.unit, self.unit, ans.prime_pow)
            else:
                cshift(ans.unit, self.unit, tmpL, ans.prime_pow.prec_cap, ans.prime_pow, False)
                csub(ans.unit, ans.unit, right.unit, ans.prime_pow.prec_cap, ans.prime_pow)
                creduce(ans.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        return ans

    def __invert__(self):
        r"""
        Returns multiplicative inverse of this element.

        EXAMPLES::

            sage: R = Zp(7, 4, 'floating-point', 'series')
            sage: ~R(2)
            4 + 3*7 + 3*7^2 + 3*7^3
            sage: ~R(0)
            infinity
            sage: ~R(7)
            7^-1
        """
        # Input should be normalized!
        cdef FPElement ans = self._new_c()
        if ans.prime_pow.in_field == 0:
            ans._parent = self._parent.fraction_field()
            ans.prime_pow = ans._parent.prime_pow
        ans.ordp = -self.ordp
        if very_pos_val(ans.ordp):
            csetone(ans.unit, ans.prime_pow)
        elif very_neg_val(ans.ordp):
            csetzero(ans.unit, ans.prime_pow)
        else:
            cinvert(ans.unit, self.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        return ans

    cpdef _mul_(self, _right):
        r"""
        Return the product of this element and ``_right``.

        EXAMPLES::

            sage: R = Zp(7, 4, 'floating-point', 'series')
            sage: R(3) * R(2) #indirect doctest
            6
            sage: R(1/2) * R(2)
            1
        """
        cdef FPElement right = _right
        if very_pos_val(self.ordp):
            if very_neg_val(right.ordp):
                raise ZeroDivisionError("Cannot multipy 0 by infinity")
            return self
        elif very_pos_val(right.ordp):
            if very_neg_val(self.ordp):
                raise ZeroDivisionError("Cannot multiply 0 by infinity")
            return right
        elif very_neg_val(self.ordp):
            return self
        elif very_neg_val(right.ordp):
            return right
        cdef FPElement ans = self._new_c()
        ans.ordp = self.ordp + right.ordp
        if overunderflow(&ans.ordp, ans.unit, ans.prime_pow):
            return ans
        cmul(ans.unit, self.unit, right.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        creduce(ans.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        return ans

    cpdef _div_(self, _right):
        r"""
        Return the quotient of this element and ``right``.

        EXAMPLES::

            sage: R = Zp(7, 4, 'floating-point', 'series')
            sage: R(3) / R(2) #indirect doctest
            5 + 3*7 + 3*7^2 + 3*7^3
            sage: R(5) / R(0)
            infinity
            sage: R(7) / R(49)
            7^-1
        """
        # Input should be normalized!
        cdef FPElement right = _right
        cdef FPElement ans = self._new_c()
        if ans.prime_pow.in_field == 0:
            ans._parent = self._parent.fraction_field()
            ans.prime_pow = ans._parent.prime_pow
        if very_pos_val(self.ordp):
            if very_pos_val(right.ordp):
                raise ZeroDivisionError("Cannot divide 0 by 0")
            ans._set_exact_zero()
        elif very_neg_val(right.ordp):
            if very_neg_val(self.ordp):
                raise ZeroDivisionError("Cannot divide infinity by infinity")
            ans._set_exact_zero()
        elif very_neg_val(self.ordp) or very_pos_val(right.ordp):
            ans._set_infinity()
        else:
            ans.ordp = self.ordp - right.ordp
            if overunderflow(&ans.ordp, ans.unit, ans.prime_pow):
                return ans
            cdivunit(ans.unit, self.unit, right.unit, ans.prime_pow.prec_cap, ans.prime_pow)
            creduce(ans.unit, ans.unit, ans.prime_pow.prec_cap, ans.prime_pow)
        return ans

    def __pow__(FPElement self, _right, dummy): # NOTE: dummy ignored, always use self.prime_pow.prec_cap
        """
        Exponentiation by an integer

        EXAMPLES::

            sage: R = ZpFP(11, 5)
            sage: R(1/2)^5
            10 + 7*11 + 11^2 + 5*11^3 + 4*11^4
            sage: R(1/32)
            10 + 7*11 + 11^2 + 5*11^3 + 4*11^4
            sage: R(1/2)^5 == R(1/32)
            True
            sage: R(3)^1000 #indirect doctest
            1 + 4*11^2 + 3*11^3 + 7*11^4
            sage: R(11)^-1
            11^-1
        """
        cdef long dummyL
        cdef mpz_t tmp
        cdef Integer right
        cdef FPElement base, pright, ans
        cdef bint exact_exp
        if isinstance(_right, (Integer, int, long, Rational)):
            if _right < 0:
                self = ~self
                _right = -_right
            exact_exp = True
        elif self.parent() is _right.parent():
            ## For extension elements, we need to switch to the
            ## fraction field sometimes in highly ramified extensions.
            exact_exp = False
            pright = _right
        else:
            self, _right = canonical_coercion(self, _right)
            return self.__pow__(_right, dummy)
        if exact_exp and _right == 0:
            ans = self._new_c()
            ans.ordp = 0
            csetone(ans.unit, ans.prime_pow)
            return ans
        if huge_val(self.ordp):
            if exact_exp:
                # We may assume from above that right > 0
                return self
            else:
                # log(0) and log(infinity) not defined
                raise ValueError("0^x and inf^x not defined for p-adic x")
        ans = self._new_c()
        if exact_exp:
            # exact_pow_helper is defined in padic_template_element.pxi
            right = exact_pow_helper(&dummyL, self.prime_pow.prec_cap, _right, self.prime_pow)
            mpz_init(tmp)
            try:
                mpz_mul_si(tmp, right.value, self.ordp)
                if overunderflow_mpz(&ans.ordp, tmp, ans.unit, ans.prime_pow):
                    return ans
                else:
                    ans.ordp = mpz_get_si(tmp)
            finally:
                mpz_clear(tmp)
            cpow(ans.unit, self.unit, right.value, ans.prime_pow.prec_cap, ans.prime_pow)
        else:
            # padic_pow_helper is defined in padic_template_element.pxi
            dummyL = padic_pow_helper(ans.unit, self.unit, self.ordp, self.prime_pow.prec_cap,
                                      pright.unit, pright.ordp, pright.prime_pow.prec_cap, self.prime_pow)
            ans.ordp = 0
        return ans

    cdef pAdicTemplateElement _lshift_c(self, long shift):
        """
        Multiplies self by `\pi^{shift}`.

        Negative shifts may truncate the result if the parent is not a
        field.

        EXAMPLES:

        We create a floating point ring::

            sage: R = ZpFP(5, 20); a = R(1000); a
            3*5^3 + 5^4

        Shifting to the right is the same as dividing by a power of
        the uniformizer `\pi` of the `p`-adic ring.::

            sage: a >> 1
            3*5^2 + 5^3

        Shifting to the left is the same as multiplying by a power of
        `\pi`::

            sage: a << 2
            3*5^5 + 5^6
            sage: a*5^2
            3*5^5 + 5^6

        Shifting by a negative integer to the left is the same as
        right shifting by the absolute value::

            sage: a << -3
            3 + 5
            sage: a >> 3
            3 + 5
        """
        if shift < 0:
            return self._rshift_c(-shift)
        elif shift == 0:
            return self
        cdef FPElement ans = self._new_c()
        # check both in case of overflow in sum; this case also includes self.ordp = maxordp
        if very_pos_val(shift) or very_pos_val(self.ordp + shift):
            # need to check that we're not shifting infinity
            if very_neg_val(self.ordp):
                raise ZeroDivisionError("Cannot multiply zero by infinity")
            ans.ordp = maxordp
            csetzero(ans.unit, ans.prime_pow)
        else:
            ans.ordp = self.ordp + shift
            ccopy(ans.unit, self.unit, ans.prime_pow)
        return ans

    cdef pAdicTemplateElement _rshift_c(self, long shift):
        """
        Divides by `\pi^{shift}`.

        Positive shifts may truncate the result if the parent is not a
        field.

        EXAMPLES::

            sage: R = ZpFP(997, 7); a = R(123456878908); a
            964*997 + 572*997^2 + 124*997^3

        Shifting to the right divides by a power of `\pi`, but
        dropping terms with negative valuation::

            sage: a >> 3
            124

        A negative shift multiplies by that power of `\pi`::

            sage: a >> -3
            964*997^4 + 572*997^5 + 124*997^6
        """
        if shift == 0:
            return self
        elif very_pos_val(self.ordp):
            if very_pos_val(shift):
                raise ZeroDivisionError("Cannot divide zero by zero")
            return self
        elif very_neg_val(self.ordp):
            if very_neg_val(shift):
                raise ZeroDivisionError("Cannot divide infinity by infinity")
            return self
        cdef FPElement ans = self._new_c()
        cdef long diff
        if self.prime_pow.in_field == 1 or shift <= self.ordp:
            if very_pos_val(shift):
                ans._set_infinity()
            elif very_neg_val(shift):
                ans._set_exact_zero()
            else:
                ans.ordp = self.ordp - shift
                ccopy(ans.unit, self.unit, ans.prime_pow)
        else:
            diff = shift - self.ordp
            if diff >= self.prime_pow.prec_cap:
                ans._set_exact_zero()
            else:
                ans.ordp = 0
                cshift(ans.unit, self.unit, -diff, ans.prime_pow.prec_cap, ans.prime_pow, False)
                ans._normalize()
        return ans

    def _repr_(self, mode=None, do_latex=False):
        """
        Returns a string representation of this element.

        INPUT:

        - ``mode`` -- allows one to override the default print mode of
          the parent (default: ``None``).

        - ``do_latex`` -- whether to return a latex representation or
          a normal one.

        EXAMPLES::

            sage: ZpFP(5,5)(1/3) # indirect doctest
            2 + 3*5 + 5^2 + 3*5^3 + 5^4
            sage: ~QpFP(5,5)(0)
            infinity
        """
        if very_neg_val(self.ordp):
            return "infinity"
        return self.parent()._printer.repr_gen(self, do_latex, mode=mode)

    def add_bigoh(self, absprec):
        """
        Returns a new element truncated modulo `\pi^{\mbox{absprec}}`.

        INPUT:

        - ``absprec`` -- an integer

        OUTPUT:

            - a new element truncated modulo `\pi^{\mbox{absprec}}`.

        EXAMPLES::

            sage: R = Zp(7,4,'floating-point','series'); a = R(8); a.add_bigoh(1)
            1
        """
        cdef long aprec, newprec
        if absprec is infinity or very_neg_val(self.ordp):
            return self
        elif isinstance(absprec, int):
            aprec = absprec
        else:
            if not isinstance(absprec, Integer):
                absprec = Integer(absprec)
            if mpz_fits_slong_p((<Integer>absprec).value) == 0:
                if mpz_sgn((<Integer>absprec).value) > 0:
                    return self
                aprec = minusmaxordp
            else:
                aprec = mpz_get_si((<Integer>absprec).value)
        if aprec >= self.ordp + self.prime_pow.prec_cap:
            return self
        cdef FPElement ans = self._new_c()
        if aprec <= self.ordp:
            ans._set_exact_zero()
        else:
            ans.ordp = self.ordp
            creduce(ans.unit, self.unit, aprec - self.ordp, ans.prime_pow)
        return ans

    cpdef bint _is_exact_zero(self) except -1:
        """
        Tests whether this element is exactly zero.

        EXAMPLES::

            sage: R = Zp(7,4,'floating-point','series'); a = R(8); a._is_exact_zero()
            False
            sage: b = R(0); b._is_exact_zero()
            True
        """
        return very_pos_val(self.ordp)

    cpdef bint _is_inexact_zero(self) except -1:
        """
        Returns True if self is indistinguishable from zero.

        EXAMPLES::

            sage: R = ZpFP(7, 5)
            sage: R(14)._is_inexact_zero()
            False
            sage: R(0)._is_inexact_zero()
            True
        """
        return very_pos_val(self.ordp)

    def is_zero(self, absprec = None):
        r"""
        Returns whether self is zero modulo `\pi^{\mbox{absprec}}`.

        INPUT:

        - ``absprec`` -- an integer

        EXAMPLES::

            sage: R = ZpFP(17, 6)
            sage: R(0).is_zero()
            True
            sage: R(17^6).is_zero()
            False
            sage: R(17^2).is_zero(absprec=2)
            True
        """
        if absprec is None:
            return very_pos_val(self.ordp)
        if very_pos_val(self.ordp):
            return True
        if absprec is infinity:
            return False
        if isinstance(absprec, int):
            return self.ordp >= absprec
        if not isinstance(absprec, Integer):
            absprec = Integer(absprec)
        return mpz_cmp_si((<Integer>absprec).value, self.ordp) <= 0

    def __nonzero__(self):
        """
        Returns True if this element is distinguishable from zero.

        For most applications, explicitly specifying the power of p
        modulo which the element is supposed to be nonzero is
        preferrable.

        EXAMPLES::

            sage: R = ZpFP(5); a = R(0); b = R(75)
            sage: bool(a), bool(b) # indirect doctest
            (False, True)
        """
        return not very_pos_val(self.ordp)

    def is_equal_to(self, _right, absprec=None):
        r"""
        Returns whether this element is equal to ``right`` modulo `p^{\mbox{absprec}}`.

        If ``absprec`` is ``None``, determines whether self and right
        have the same value.

        INPUT:

        - ``right`` -- a p-adic element with the same parent
        - ``absprec`` -- a positive integer or ``None`` (default: ``None``)

        EXAMPLES::

            sage: R = ZpFP(2, 6)
            sage: R(13).is_equal_to(R(13))
            True
            sage: R(13).is_equal_to(R(13+2^10))
            True
            sage: R(13).is_equal_to(R(17), 2)
            True
            sage: R(13).is_equal_to(R(17), 5)
            False
        """
        cdef FPElement right
        cdef long aprec, rprec
        if self.parent() is _right.parent():
            right = _right
        else:
            right = self.parent().coerce(_right)
        if very_neg_val(self.ordp):
            if very_neg_val(right.ordp):
                return True
            return False
        elif very_neg_val(right.ordp):
            return False
        if absprec is None or absprec is infinity:
            return ((self.ordp == right.ordp) and
                    (ccmp(self.unit, right.unit, self.prime_pow.prec_cap, False, False, self.prime_pow) == 0))
        if not isinstance(absprec, Integer):
            absprec = Integer(absprec)
        if mpz_cmp_si((<Integer>absprec).value, self.ordp) <= 0:
            if mpz_cmp_si((<Integer>absprec).value, right.ordp) <= 0:
                return True
            return False
        elif mpz_cmp_si((<Integer>absprec).value, right.ordp) <= 0:
            return False
        if self.ordp != right.ordp:
            return False
        if mpz_cmp_si((<Integer>absprec).value, maxordp) >= 0:
            return ccmp(self.unit, right.unit, self.prime_pow.prec_cap, False, False, self.prime_pow) == 0
        aprec = mpz_get_si((<Integer>absprec).value)
        rprec = aprec - self.ordp
        if rprec > self.prime_pow.prec_cap:
            rprec = self.prime_pow.prec_cap
        return ccmp(self.unit,
                    right.unit,
                    rprec,
                    rprec < self.prime_pow.prec_cap,
                    rprec < right.prime_pow.prec_cap,
                    self.prime_pow) == 0

    cdef int _cmp_units(self, pAdicGenericElement _right) except -2:
        """
        Comparison of units, used in equality testing.

        EXAMPLES::

            sage: R = ZpFP(5)
            sage: a = R(17); b = R(0,3); c = R(85,7); d = R(2, 1)
            sage: any([a == b, a == c, b == c, b == d, c == d, a == d]) # indirect doctest
            False
            sage: all([a == a, b == b, c == c, d == d])
            True
        """
        cdef FPElement right = _right
        return ccmp(self.unit, right.unit, self.prime_pow.prec_cap, False, False, self.prime_pow)

    cdef pAdicTemplateElement lift_to_precision_c(self, long absprec):
        """
        Lifts this element to another with precision at least absprec.

        Since floating point elements don't track precision, this
        function just returns the same element.

        EXAMPLES::

            sage: R = ZpFP(5);
            sage: a = R(77, 2); a
            2
            sage: a.lift_to_precision(17) # indirect doctest
            2
        """
        return self

    def list(self, lift_mode = 'simple', start_val = None):
        r"""
        Returns a list of coefficients in a power series expansion of
        this element in terms of `\pi`.  If this is a field element,
        they start at `\pi^{\mbox{valuation}}`, if a ring element at `\pi^0`.

        For each lift mode, this function returns a list of `a_i` so
        that this element can be expressed as

        .. MATH::

            \pi^v \cdot \sum_{i=0}^\infty a_i \pi^i

        where `v` is the valuation of this element when the parent is
        a field, and `v = 0` otherwise.

        Different lift modes affect the choice of `a_i`.  When
        ``lift_mode`` is ``'simple'``, the resulting `a_i` will be
        non-negative: if the residue field is `\mathbb{F}_p` then they
        will be integers with `0 \le a_i < p`; otherwise they will be
        a list of integers in the same range giving the coefficients
        of a polynomial in the indeterminant representing the maximal
        unramified subextension.

        Choosing ``lift_mode`` as ``'smallest'`` is similar to
        ``'simple'``, but uses a balanced representation `-p/2 < a_i
        \le p/2`.

        Finally, setting ``lift_mode = 'teichmuller'`` will yield
        Teichmuller representatives for the `a_i`: `a_i^q = a_i`.  In
        this case the `a_i` will also be `p`-adic elements.

        INPUT:

        - ``lift_mode`` -- ``'simple'``, ``'smallest'`` or
          ``'teichmuller'`` (default: ``'simple'``)

        - ``start_val`` -- start at this valuation rather than the
          default (`0` or the valuation of this element).  If
          ``start_val`` is larger than the valuation of this element
          a ``ValueError`` is raised.

        OUTPUT:

        - the list of coefficients of this element.  For base elements
          these will be integers if ``lift_mode`` is ``'simple'`` or
          ``'smallest'``, and elements of ``self.parent()`` if
          ``lift_mode`` is ``'teichmuller'``.

        .. NOTE::

            Use slice operators to get a particular range.

        EXAMPLES::

            sage: R = ZpFP(7,6); a = R(12837162817); a
            3 + 4*7 + 4*7^2 + 4*7^4
            sage: L = a.list(); L
            [3, 4, 4, 0, 4]
            sage: sum([L[i] * 7^i for i in range(len(L))]) == a
            True
            sage: L = a.list('smallest'); L
            [3, -3, -2, 1, -3, 1]
            sage: sum([L[i] * 7^i for i in range(len(L))]) == a
            True
            sage: L = a.list('teichmuller'); L
            [3 + 4*7 + 6*7^2 + 3*7^3 + 2*7^5,
            0,
            5 + 2*7 + 3*7^3 + 6*7^4 + 4*7^5,
            1,
            3 + 4*7 + 6*7^2 + 3*7^3 + 2*7^5,
            5 + 2*7 + 3*7^3 + 6*7^4 + 4*7^5]
            sage: sum([L[i] * 7^i for i in range(len(L))])
            3 + 4*7 + 4*7^2 + 4*7^4

            sage: R(0).list()
            []

            sage: R = QpFP(7,4); a = R(6*7+7**2); a.list()
            [6, 1]
            sage: a.list('smallest')
            [-1, 2]
            sage: a.list('teichmuller')
            [6 + 6*7 + 6*7^2 + 6*7^3,
            2 + 4*7 + 6*7^2 + 3*7^3,
            3 + 4*7 + 6*7^2 + 3*7^3,
            3 + 4*7 + 6*7^2 + 3*7^3]
        """
        R = self.parent()
        if start_val is not None and start_val > self.ordp:
            raise ValueError("starting valuation must be smaller than the element's valuation.  See slice()")
        if very_pos_val(self.ordp):
            return []
        elif very_neg_val(self.ordp):
            if lift_mode == 'teichmuller':
                return [R(1)]
            elif R.f() == 1:
                return [ZZ(1)]
            else:
                return [[ZZ(1)]]
        if lift_mode == 'teichmuller':
            ulist = self.teichmuller_list()
        elif lift_mode == 'simple':
            ulist = clist(self.unit, self.prime_pow.prec_cap, True, self.prime_pow)
        elif lift_mode == 'smallest':
            ulist = clist(self.unit, self.prime_pow.prec_cap, False, self.prime_pow)
        else:
            raise ValueError("unknown lift_mode")
        if (self.prime_pow.in_field == 0 and self.ordp > 0) or start_val is not None:
            if lift_mode == 'teichmuller':
                zero = R(0)
            else:
                # needs to be defined in the linkage file.
                zero = _list_zero
            if start_val is None:
                v = self.ordp
            else:
                v = self.ordp - start_val
            ulist = [zero] * v + ulist
        return ulist

    def teichmuller_list(self):
        r"""
        Returns a list [`a_0`, `a_1`,..., `a_n`] such that

        - `a_i^q = a_i`

        - self.unit_part() = `\sum_{i = 0}^n a_i \pi^i`

        EXAMPLES::

            sage: R = ZpFP(5,5); R(14).list('teichmuller') #indirect doctest
            [4 + 4*5 + 4*5^2 + 4*5^3 + 4*5^4,
            3 + 3*5 + 2*5^2 + 3*5^3 + 5^4,
            2 + 5 + 2*5^2 + 5^3 + 3*5^4,
            1,
            4 + 4*5 + 4*5^2 + 4*5^3 + 4*5^4]
        """
        cdef FPElement list_elt
        ans = PyList_New(0)
        if very_pos_val(self.ordp):
            return ans
        if very_neg_val(self.ordp):
            list_elt = self._new_c()
            csetone(list_elt.unit, self.prime_pow)
            list_elt.ordp = 0
            PyList_Append(ans, list_elt)
            return ans
        cdef long prec_cap = self.prime_pow.prec_cap
        cdef long curpower = prec_cap
        cdef FPElement tmp = self._new_c()
        ccopy(tmp.unit, self.unit, self.prime_pow)
        while not ciszero(tmp.unit, tmp.prime_pow) and curpower > 0:
            list_elt = self._new_c()
            cteichmuller(list_elt.unit, tmp.unit, prec_cap, self.prime_pow)
            if ciszero(list_elt.unit, self.prime_pow):
                list_elt.ordp = maxordp
                cshift_notrunc(tmp.unit, tmp.unit, -1, prec_cap, self.prime_pow)
            else:
                list_elt.ordp = 0
                csub(tmp.unit, tmp.unit, list_elt.unit, prec_cap, self.prime_pow)
                cshift_notrunc(tmp.unit, tmp.unit, -1, prec_cap, self.prime_pow)
                creduce(tmp.unit, tmp.unit, prec_cap, self.prime_pow)
            curpower -= 1
            PyList_Append(ans, list_elt)
        return ans

    def _teichmuller_set_unsafe(self):
        """
        Sets this element to the Teichmuller representative with the
        same residue.

        .. WARNING::

            This function modifies the element, which is not safe.
            Elements are supposed to be immutable.

        EXAMPLES::

            sage: R = ZpFP(17,5); a = R(11)
            sage: a
            11
            sage: a._teichmuller_set_unsafe(); a
            11 + 14*17 + 2*17^2 + 12*17^3 + 15*17^4
            sage: a.list('teichmuller')
            [11 + 14*17 + 2*17^2 + 12*17^3 + 15*17^4]

        Note that if you set an element which is congruent to 0 you
        get 0 to maximum precision::

            sage: b = R(17*5); b
            5*17
            sage: b._teichmuller_set_unsafe(); b
            0
        """
        if self.ordp > 0:
            self._set_exact_zero()
        elif self.ordp < 0:
            raise ValueError("cannot set negative valuation element to Teichmuller representative.")
        else:
            cteichmuller(self.unit, self.unit, self.prime_pow.prec_cap, self.prime_pow)

    def precision_absolute(self):
        """
        The absolute precision of this element.

        EXAMPLES::

            sage: R = Zp(7,4,'floating-point'); a = R(7); a.precision_absolute()
            5
            sage: R(0).precision_absolute()
            +Infinity
            sage: (~R(0)).precision_absolute()
            -Infinity
        """
        if very_pos_val(self.ordp):
            return infinity
        elif very_neg_val(self.ordp):
            return -infinity
        cdef Integer ans = PY_NEW(Integer)
        mpz_set_si(ans.value, self.ordp + self.prime_pow.prec_cap)
        return ans

    def precision_relative(self):
        r"""
        The relative precision of this element.

        EXAMPLES::

            sage: R = Zp(7,4,'floating-point'); a = R(7); a.precision_relative()
            4
            sage: R(0).precision_relative()
            0
            sage: (~R(0)).precision_relative()
            0
        """
        cdef Integer ans = PY_NEW(Integer)
        if huge_val(self.ordp):
            mpz_set_si(ans.value, 0)
        else:
            mpz_set_si(ans.value, self.prime_pow.prec_cap)
        return ans

    cpdef pAdicTemplateElement unit_part(FPElement self):
        r"""
        Returns the unit part of this element.

        If the valuation of this element is positive, then the high
        digits of the result will be zero.

        EXAMPLES::

            sage: R = Zp(17, 4, 'floating-point')
            sage: R(5).unit_part()
            5
            sage: R(18*17).unit_part()
            1 + 17
            sage: R(0).unit_part()
            Traceback (most recent call last):
            ...
            ValueError: unit part of 0 and infinity not defined
            sage: type(R(5).unit_part())
            <type 'sage.rings.padics.padic_floating_point_element.pAdicFloatingPointElement'>
            sage: R = ZpFP(5, 5); a = R(75); a.unit_part()
            3
        """
        if huge_val(self.ordp):
            raise ValueError("unit part of 0 and infinity not defined")
        cdef FPElement ans = (<FPElement>self)._new_c()
        ans.ordp = 0
        ccopy(ans.unit, (<FPElement>self).unit, ans.prime_pow)
        return ans

    cdef long valuation_c(self):
        """
        Returns the valuation of this element.

        If this element is an exact zero, returns ``maxordp``, which is defined as
        ``(1L << (sizeof(long) * 8 - 2))-1``.

        If this element is infinity, returns ``-maxordp``.

        TESTS::

            sage: R = ZpFP(5, 5); R(1).valuation() #indirect doctest
            0
            sage: R = Zp(17, 4,'floating-point')
            sage: a = R(2*17^2)
            sage: a.valuation()
            2
            sage: R = Zp(5, 4,'floating-point')
            sage: R(0).valuation()
            +Infinity
            sage: (~R(0)).valuation()
            -Infinity
            sage: R(1).valuation()
            0
            sage: R(2).valuation()
            0
            sage: R(5).valuation()
            1
            sage: R(10).valuation()
            1
            sage: R(25).valuation()
            2
            sage: R(50).valuation()
            2
        """
        return self.ordp

    cpdef val_unit(self, p=None):
        """
        Returns a 2-tuple, the first element set to the valuation of
        this element, and the second to the unit part.

        If this element is either zero or infinity, raises an error.

        EXAMPLES::

            sage: R = ZpFP(5,5)
            sage: a = R(75); b = a - a
            sage: a.val_unit()
            (2, 3)
            sage: b.val_unit()
            Traceback (most recent call last):
            ...
            ValueError: unit part of 0 and infinity not defined
        """
        if p is not None and p != self.parent().prime():
            raise ValueError('Ring (%s) residue field of the wrong characteristic.'%self.parent())
        if huge_val(self.ordp):
            raise ValueError("unit part of 0 and infinity not defined")
        cdef Integer valuation = PY_NEW(Integer)
        mpz_set_si(valuation.value, self.ordp)
        cdef FPElement unit = self._new_c()
        unit.ordp = 0
        ccopy(unit.unit, self.unit, unit.prime_pow)
        return valuation, unit

    def __hash__(self):
        """
        Hashing.

        EXAMPLES::

            sage: R = ZpFP(11, 5)
            sage: hash(R(3)) == hash(3)
            True
        """
        if very_pos_val(self.ordp):
            return 0
        if very_neg_val(self.ordp):
            return 314159
        return chash(self.unit, self.ordp, self.prime_pow.prec_cap, self.prime_pow) ^ self.ordp

cdef class pAdicCoercion_ZZ_FP(RingHomomorphism_coercion):
    """
    The canonical inclusion from the integer ring to a floating point ring.

    EXAMPLES::

        sage: f = ZpFP(5).coerce_map_from(ZZ); f
        Ring Coercion morphism:
          From: Integer Ring
          To:   5-adic Ring with floating precision 20
    """
    def __init__(self, R):
        """
        Initialization.

        EXAMPLES::

            sage: f = ZpFP(5).coerce_map_from(ZZ); type(f)
            <type 'sage.rings.padics.padic_floating_point_element.pAdicCoercion_ZZ_FP'>
        """
        RingHomomorphism_coercion.__init__(self, ZZ.Hom(R), check=False)
        self._zero = <FPElement?>R._element_constructor(R, 0)
        self._section = pAdicConvert_FP_ZZ(R)

    cdef dict _extra_slots(self, dict _slots):
        """
        Helper for copying and pickling.

        EXAMPLES::

            sage: f = ZpFP(5).coerce_map_from(ZZ)
            sage: g = copy(f) # indirect doctest
            sage: g == f
            True
            sage: g(6)
            1 + 5
            sage: g(6) == f(6)
            True
        """
        _slots['_zero'] = self._zero
        _slots['_section'] = self._section
        return RingHomomorphism_coercion._extra_slots(self, _slots)

    cdef _update_slots(self, dict _slots):
        """
        Helper for copying and pickling.

        EXAMPLES::

            sage: f = ZpFP(5).coerce_map_from(ZZ)
            sage: g = copy(f) # indirect doctest
            sage: g == f
            True
            sage: g(6)
            1 + 5
            sage: g(6) == f(6)
            True
        """
        self._zero = _slots['_zero']
        self._section = _slots['_section']
        RingHomomorphism_coercion._update_slots(self, _slots)

    cpdef Element _call_(self, x):
        """
        Evaluation.

        EXAMPLES::

            sage: f = ZpFP(5).coerce_map_from(ZZ)
            sage: f(0).parent()
            5-adic Ring with floating precision 20
            sage: f(5)
            5
        """
        if mpz_sgn((<Integer>x).value) == 0:
            return self._zero
        cdef FPElement ans = self._zero._new_c()
        ans.ordp = cconv_mpz_t(ans.unit, (<Integer>x).value, ans.prime_pow.prec_cap, False, ans.prime_pow)
        return ans

    cpdef Element _call_with_args(self, x, args=(), kwds={}):
        """
        This function is used when some precision cap is passed in (relative or absolute or both).

        INPUT:

        - ``x`` -- an Integer

        - ``absprec``, or the first positional argument -- the maximum
          absolute precision (unused for floating point elements).

        - ``relprec``, or the second positional argument -- the
          maximum relative precision (unused for floating point
          elements)

        EXAMPLES::

            sage: R = ZpFP(5,4)
            sage: type(R(10,2))
            <type 'sage.rings.padics.padic_floating_point_element.pAdicFloatingPointElement'>
            sage: R(30,2)
            5
            sage: R(30,3,2)
            5 + 5^2
            sage: R(30,absprec=2)
            5
            sage: R(30,relprec=2)
            5 + 5^2
            sage: R(30,absprec=1)
            0
            sage: R(30,empty=True)
            0
        """
        cdef long val, aprec, rprec
        if mpz_sgn((<Integer>x).value) == 0:
            return self._zero
        _process_args_and_kwds(&aprec, &rprec, args, kwds, False, self._zero.prime_pow)
        val = get_ordp(x, self._zero.prime_pow)
        if aprec - val < rprec:
            rprec = aprec - val
        if rprec <= 0:
            return self._zero
        cdef FPElement ans = self._zero._new_c()
        ans.ordp = cconv_mpz_t(ans.unit, (<Integer>x).value, rprec, False, ans.prime_pow)
        return ans

    def section(self):
        """
        Returns a map back to ZZ that approximates an element of this
        `p`-adic ring by an integer.

        EXAMPLES::

            sage: f = ZpFP(5).coerce_map_from(ZZ).section()
            sage: f(ZpFP(5)(-1)) - 5^20
            -1
        """
        return self._section

cdef class pAdicConvert_FP_ZZ(RingMap):
    """
    The map from a floating point ring back to ZZ that returns the the smallest
    non-negative integer approximation to its input which is accurate up to the precision.

    If the input is not in the closure of the image of ZZ, raises a ValueError.

    EXAMPLES::

        sage: f = ZpFP(5).coerce_map_from(ZZ).section(); f
        Set-theoretic ring morphism:
          From: 5-adic Ring with floating precision 20
          To:   Integer Ring
    """
    def __init__(self, R):
        """
        Initialization.

        EXAMPLES::

            sage: f = ZpFP(5).coerce_map_from(ZZ).section(); type(f)
            <type 'sage.rings.padics.padic_floating_point_element.pAdicConvert_FP_ZZ'>
            sage: f.category()
            Category of homsets of sets
        """
        if R.degree() > 1 or R.characteristic() != 0 or R.residue_characteristic() == 0:
            RingMap.__init__(self, Hom(R, ZZ, SetsWithPartialMaps()))
        else:
            RingMap.__init__(self, Hom(R, ZZ, Sets()))

    cpdef Element _call_(self, _x):
        """
        Evaluation.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(ZZ).section()
            sage: f(QpFP(5)(-1)) - 5^20
            -1
            sage: f(QpFP(5)(5))
            5
            sage: f(QpFP(5)(0))
            0
            sage: f(~QpFP(5)(5))
            Traceback (most recent call last):
            ...
            ValueError: negative valuation
            sage: f(~QpFP(5)(0))
            Traceback (most recent call last):
            ...
            ValueError: Infinity cannot be converted to a rational
        """
        cdef Integer ans = PY_NEW(Integer)
        cdef FPElement x = _x
        if very_pos_val(x.ordp):
            mpz_set_ui(ans.value, 0)
        elif very_neg_val(x.ordp):
            raise ValueError("Infinity cannot be converted to a rational")
        else:
            cconv_mpz_t_out(ans.value, x.unit, x.ordp, x.prime_pow.prec_cap, x.prime_pow)
        return ans

cdef class pAdicCoercion_QQ_FP(RingHomomorphism_coercion):
    """
    The canonical inclusion from the rationals to a floating point field.

    EXAMPLES::

        sage: f = QpFP(5).coerce_map_from(QQ); f
        Ring Coercion morphism:
          From: Rational Field
          To:   5-adic Field with floating precision 20
    """
    def __init__(self, R):
        """
        Initialization.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ); type(f)
            <type 'sage.rings.padics.padic_floating_point_element.pAdicCoercion_QQ_FP'>
        """
        RingHomomorphism_coercion.__init__(self, QQ.Hom(R), check=False)
        self._zero = R._element_constructor(R, 0)
        self._section = pAdicConvert_FP_QQ(R)

    cdef dict _extra_slots(self, dict _slots):
        """
        Helper for copying and pickling.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ)
            sage: g = copy(f)   # indirect doctest
            sage: g
            Ring Coercion morphism:
              From: Rational Field
              To:   5-adic Field with floating precision 20
            sage: g == f
            True
            sage: g is f
            False
            sage: g(6)
            1 + 5
            sage: g(6) == f(6)
            True
        """
        _slots['_zero'] = self._zero
        _slots['_section'] = self._section
        return RingHomomorphism_coercion._extra_slots(self, _slots)

    cdef _update_slots(self, dict _slots):
        """
        Helper for copying and pickling.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ)
            sage: g = copy(f)   # indirect doctest
            sage: g
            Ring Coercion morphism:
              From: Rational Field
              To:   5-adic Field with floating precision 20
            sage: g == f
            True
            sage: g is f
            False
            sage: g(6)
            1 + 5
            sage: g(6) == f(6)
            True
        """
        self._zero = _slots['_zero']
        self._section = _slots['_section']
        RingHomomorphism_coercion._update_slots(self, _slots)

    cpdef Element _call_(self, x):
        """
        Evaluation.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ)
            sage: f(0).parent()
            5-adic Field with floating precision 20
            sage: f(1/5)
            5^-1
            sage: f(1/4)
            4 + 3*5 + 3*5^2 + 3*5^3 + 3*5^4 + 3*5^5 + 3*5^6 + 3*5^7 + 3*5^8 + 3*5^9 + 3*5^10 + 3*5^11 + 3*5^12 + 3*5^13 + 3*5^14 + 3*5^15 + 3*5^16 + 3*5^17 + 3*5^18 + 3*5^19
            sage: f(1/4, 5)
            4 + 3*5 + 3*5^2 + 3*5^3 + 3*5^4
        """
        if mpq_sgn((<Rational>x).value) == 0:
            return self._zero
        cdef FPElement ans = self._zero._new_c()
        ans.ordp = cconv_mpq_t(ans.unit, (<Rational>x).value, ans.prime_pow.prec_cap, False, self._zero.prime_pow)
        return ans

    cpdef Element _call_with_args(self, x, args=(), kwds={}):
        """
        This function is used when some precision cap is passed in
        (relative or absolute or both).

        See the documentation for
        :meth:`pAdicCappedRelativeElement.__init__` for more details.

        EXAMPLES::

            sage: R = QpFP(5,4)
            sage: type(R(10/3,2))
            <type 'sage.rings.padics.padic_floating_point_element.pAdicFloatingPointElement'>
            sage: R(10/3,2)
            4*5
            sage: R(10/3,3,1)
            4*5
            sage: R(10/3,absprec=2)
            4*5
            sage: R(10/3,relprec=2)
            4*5 + 5^2
            sage: R(10/3,absprec=1)
            0
            sage: R(3/100,absprec=-1)
            2*5^-2
        """
        cdef long val, aprec, rprec
        cdef FPElement ans
        _process_args_and_kwds(&aprec, &rprec, args, kwds, False, self._zero.prime_pow)
        if mpq_sgn((<Rational>x).value) == 0:
            return self._zero
        val = get_ordp(x, self._zero.prime_pow)
        if aprec <= val:
            return self._zero
        ans = self._zero._new_c()
        rprec = min(rprec, aprec - val)
        ans.ordp = cconv_mpq_t(ans.unit, (<Rational>x).value, rprec, False, self._zero.prime_pow)
        return ans

    def section(self):
        """
        Returns a map back to the rationals that approximates an element by
        a rational number.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ).section()
            sage: f(QpFP(5)(1/4))
            1/4
            sage: f(QpFP(5)(1/5))
            1/5
        """
        return self._section

cdef class pAdicConvert_FP_QQ(RingMap):
    """
    The map from the floating point ring back to the rationals that returns a
    rational approximation of its input.

    EXAMPLES::

        sage: f = QpFP(5).coerce_map_from(QQ).section(); f
        Set-theoretic ring morphism:
          From: 5-adic Field with floating precision 20
          To:   Rational Field
    """
    def __init__(self, R):
        """
        Initialization.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ).section(); type(f)
            <type 'sage.rings.padics.padic_floating_point_element.pAdicConvert_FP_QQ'>
            sage: f.category()
            Category of homsets of sets with partial maps
        """
        RingMap.__init__(self, Hom(R, QQ, SetsWithPartialMaps()))

    cpdef Element _call_(self, _x):
        """
        Evaluation.

        EXAMPLES::

            sage: f = QpFP(5).coerce_map_from(QQ).section()
            sage: f(QpFP(5)(-1))
            -1
            sage: f(QpFP(5)(0))
            0
            sage: f(QpFP(5)(1/5))
            1/5
        """
        cdef Rational ans = Rational.__new__(Rational)
        cdef FPElement x =  _x
        if very_pos_val(x.ordp):
            mpq_set_ui(ans.value, 0, 1)
        elif very_neg_val(x.ordp):
            raise ValueError("Infinity cannot be converted to a rational")
        else:
            cconv_mpq_t_out(ans.value, x.unit, x.ordp, x.prime_pow.prec_cap, x.prime_pow)
        return ans

cdef class pAdicConvert_QQ_FP(Morphism):
    """
    The inclusion map from QQ to a floating point ring.

    EXAMPLES::

        sage: f = ZpFP(5).convert_map_from(QQ); f
        Generic morphism:
          From: Rational Field
          To:   5-adic Ring with floating precision 20
    """
    def __init__(self, R):
        """
        Initialization.

        EXAMPLES::

            sage: f = ZpFP(5).convert_map_from(QQ); type(f)
            <type 'sage.rings.padics.padic_floating_point_element.pAdicConvert_QQ_FP'>
        """
        Morphism.__init__(self, Hom(QQ, R, SetsWithPartialMaps()))
        self._zero = R._element_constructor(R, 0)

    cdef dict _extra_slots(self, dict _slots):
        """
        Helper for copying and pickling.

        EXAMPLES::

            sage: f = ZpFP(5).convert_map_from(QQ)
            sage: g = copy(f) # indirect doctest
            sage: g == f # todo: comparison not implemented
            True
            sage: g(1/6)
            1 + 4*5 + 4*5^3 + 4*5^5 + 4*5^7 + 4*5^9 + 4*5^11 + 4*5^13 + 4*5^15 + 4*5^17 + 4*5^19
            sage: g(1/6) == f(1/6)
            True
        """
        _slots['_zero'] = self._zero
        return Morphism._extra_slots(self, _slots)

    cdef _update_slots(self, dict _slots):
        """
        Helper for copying and pickling.

        EXAMPLES::

            sage: f = ZpFP(5).convert_map_from(QQ)
            sage: g = copy(f) # indirect doctest
            sage: g == f # todo: comparison not implemented
            True
            sage: g(1/6)
            1 + 4*5 + 4*5^3 + 4*5^5 + 4*5^7 + 4*5^9 + 4*5^11 + 4*5^13 + 4*5^15 + 4*5^17 + 4*5^19
            sage: g(1/6) == f(1/6)
            True
        """
        self._zero = _slots['_zero']
        Morphism._update_slots(self, _slots)

    cpdef Element _call_(self, x):
        """
        Evaluation.

        EXAMPLES::

            sage: f = ZpFP(5,4).convert_map_from(QQ)
            sage: f(1/7)
            3 + 3*5 + 2*5^3
            sage: f(0/1)
            0
        """
        if mpq_sgn((<Rational>x).value) == 0:
            return self._zero
        cdef FPElement ans = self._zero._new_c()
        ans.ordp = cconv_mpq_t(ans.unit, (<Rational>x).value, ans.prime_pow.prec_cap, False, ans.prime_pow)
        if ans.ordp < 0:
            raise ValueError("p divides the denominator")
        return ans

    cpdef Element _call_with_args(self, x, args=(), kwds={}):
        """
        This function is used when some precision cap is passed in (relative or absolute or both).

        INPUT:

        - ``x`` -- a Rational

        - ``absprec``, or the first positional argument -- the maximum
          absolute precision (unused for floating point elements).

        - ``relprec``, or the second positional argument -- the
          maximum relative precision (unused for floating point
          elements)

        EXAMPLES::

            sage: R = ZpFP(5,4)
            sage: type(R(1/7,2))
            <type 'sage.rings.padics.padic_floating_point_element.pAdicFloatingPointElement'>
            sage: R(1/7,2)
            3 + 3*5
            sage: R(1/7,3,2)
            3 + 3*5
            sage: R(1/7,absprec=2)
            3 + 3*5
            sage: R(5/7,relprec=2)
            3*5 + 3*5^2
            sage: R(1/7,absprec=1)
            3
            sage: R(1/7,empty=True)
            0
        """
        cdef long val, aprec, rprec
        if mpq_sgn((<Rational>x).value) == 0:
            return self._zero
        _process_args_and_kwds(&aprec, &rprec, args, kwds, False, self._zero.prime_pow)
        val = get_ordp(x, self._zero.prime_pow)
        rprec = min(rprec, aprec - val)
        if rprec <= 0:
            return self._zero
        cdef FPElement ans = self._zero._new_c()
        ans.ordp = cconv_mpq_t(ans.unit, (<Rational>x).value, rprec, False, ans.prime_pow)
        if ans.ordp < 0:
            raise ValueError("p divides the denominator")
        return ans

def unpickle_fpe_v2(cls, parent, unit, ordp):
    """
    Unpickles a floating point element.

    EXAMPLES::

        sage: from sage.rings.padics.padic_floating_point_element import pAdicFloatingPointElement, unpickle_fpe_v2
        sage: R = ZpFP(5)
        sage: a = unpickle_fpe_v2(pAdicFloatingPointElement, R, 17, 2); a
        2*5^2 + 3*5^3
        sage: a.parent() is R
        True
    """
    cdef FPElement ans = cls.__new__(cls)
    ans._parent = parent
    ans.prime_pow = <PowComputer_?>parent.prime_pow
    cconstruct(ans.unit, ans.prime_pow)
    cunpickle(ans.unit, unit, ans.prime_pow)
    ans.ordp = ordp
    return ans