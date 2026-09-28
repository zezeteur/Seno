import 'package:flutter/services.dart';

/// Garde uniquement les chiffres et les groupe 2 par 2 : « 0701020304 » → « 07 01 02 03 04 »
class PairDigitsFormatter extends TextInputFormatter {
  final int maxDigits;

  PairDigitsFormatter({required this.maxDigits});

  /// « 0701020304 » → « 07 01 02 03 04 » (valeur initiale d'un champ)
  static String group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i.isEven) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);

    // Effacement d'un espace seul : retirer aussi le chiffre qui le précède
    final deletedOnlySpace = oldValue.text.length - newValue.text.length == 1 &&
        oldValue.text.replaceAll(' ', '') == digits &&
        digits.isNotEmpty;
    if (deletedOnlySpace) digits = digits.substring(0, digits.length - 1);

    final text = group(digits);
    // Curseur toujours en fin de saisie
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
