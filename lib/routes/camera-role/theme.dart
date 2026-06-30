//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';

const cameraRoleBg = Color(0xFF050505);
const cameraRoleEmerald = Color(0xFF10B981);
const cameraRoleBlue = Color(0xFF8BB3EE);
const cameraRoleAmber = Color(0xFFF0C08A);
const cameraRoleDanger = Color(0xFFF29BA0);
const cameraRoleWhite40 = Color(0x66FFFFFF);
const cameraRoleWhite20 = Color(0x33FFFFFF);

double cameraRoleFlowScale(BoxConstraints c) =>
    math.min(c.maxWidth / 290, c.maxHeight / 652);

Widget cameraRoleDot(double size, Color color) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
);
