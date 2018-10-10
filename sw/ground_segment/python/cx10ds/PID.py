#!/usr/bin/python
#
# This file is part of IvPID.
# Copyright (C) 2015 Ivmech Mechatronics Ltd. <bilgi@ivmech.com>
#
# IvPID is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# IvPID is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# title           :PID.py
# description     :python pid controller
# author          :Caner Durmusoglu
# date            :20151218
# version         :0.1
# notes           :
# python_version  :2.7
# ==============================================================================

"""Ivmech PID Controller is simple implementation of a Proportional-Integral-Derivative (PID) Controller in the Python Programming Language.
More information about PID Controller: http://en.wikipedia.org/wiki/PID_controller
"""
import time

class PID:
    """PID Controller
    """

    def __init__(self, P=0.2, I=0.0, D=0.0):

        self.Kp = P
        self.Ki = I
        self.Kd = D

        self.sample_time = 0.00
        self.current_time = time.time()
        self.last_time = self.current_time

        self.clear()

    def clear(self):
        """Clears PID computations and coefficients"""
        self.SetPoint = 0.0

        self.PTerm = 0.0
        self.ITerm = 0.0
        self.DTerm = 0.0
        self.last_error = 0.0
        self.delta_error = 0.0

        # Windup Guard
        self.int_error = 0.0
        self.windup_guard = 100.0

        self.output = 0.0

    def clear_PID(self):
        """Clears PID computations only"""
        self.last_error = 0.0
        self.delta_error = 0.0
        self.int_error = 0.0
        self.output = 0.0

    def update(self, feedback_value, in_flight=True, coef=1.0, max_error=None):
        """Calculates PID value for given reference feedback

        .. math::
            u(t) = K_p e(t) + K_i \int_{0}^{t} e(t)dt + K_d {de}/{dt}

        .. figure:: images/pid_1.png
           :align:   center

           Test PID with Kp=1.2, Ki=1, Kd=0.001 (test_pid.py)

        """
        error = self.SetPoint - feedback_value
        if max_error is not None:
            if error > max_error:
                error = max_error
            elif: error < -max_error:
                error = -max_error

        self.current_time = time.time()
        delta_time = self.current_time - self.last_time
        if delta_time > 1.: # FIXME hardcoded timeout
            # Remember last time and last error for next calculation
            self.last_time = self.current_time
            self.last_error = error
            print("delta {}".format(delta_time))
            return # too long since last update

        if (delta_time >= self.sample_time):
            self.PTerm = self.Kp * error
            if in_flight:
                self.int_error += error * delta_time
                self.ITerm = self.Ki * self.int_error
                if (self.ITerm < -self.windup_guard):
                    self.ITerm = -self.windup_guard
                    print("windup - sat")
                elif (self.ITerm > self.windup_guard):
                    self.ITerm = self.windup_guard
                    print("windup + sat")
            else:
                self.int_error = 0.0
                self.ITerm = 0.0

            self.DTerm = 0.0
            if delta_time > 0:
                self.delta_error = error - self.last_error
                self.DTerm = self.Kd * self.delta_error / delta_time

            # Remember last time and last error for next calculation
            self.last_time = self.current_time
            self.last_error = error

            self.output = (coef * self.PTerm) + self.ITerm + (coef * self.DTerm)

    def setKp(self, proportional_gain):
        """Determines how aggressively the PID reacts to the current error with setting Proportional Gain"""
        self.Kp = proportional_gain
        print("set Kp {}".format(self.Kp))

    def setKi(self, integral_gain):
        """Determines how aggressively the PID reacts to the current error with setting Integral Gain"""
        self.Ki = integral_gain
        print("set Ki {}".format(self.Ki))

    def setKd(self, derivative_gain):
        """Determines how aggressively the PID reacts to the current error with setting Derivative Gain"""
        self.Kd = derivative_gain
        print("set Kd {}".format(self.Kd))

    def setWindup(self, windup):
        """Integral windup, also known as integrator windup or reset windup,
        refers to the situation in a PID feedback controller where
        a large change in setpoint occurs (say a positive change)
        and the integral terms accumulates a significant error
        during the rise (windup), thus overshooting and continuing
        to increase as this accumulated error is unwound
        (offset by errors in the other direction).
        The specific problem is the excess overshooting.
        """
        self.windup_guard = windup
        print("set windup {}".format(self.windup_guard))

    def setSampleTime(self, sample_time):
        """PID that should be updated at a regular interval.
        Based on a pre-determined sampe time, the PID decides if it should compute or return immediately.
        """
        self.sample_time = sample_time