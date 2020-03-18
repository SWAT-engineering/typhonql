module lang::tydown::IDE

import util::IDE;
import lang::tydown::TyDown;
import ParseTree;
import vis::Figure;


//public data FontProperty
//	= bold()
//	| italic()
//	| font(str name, int size)
//	| foregroundColor(Color color)
//	| backgroundColor(Color color)
//	;

Contribution myCategories() {
	// colors would be even better if background was #FDF6E3 and text #FDF6E3
	return categories((
		// default categories
		//"Normal": {},
		"H1": {bold(), italic()}, 
		"H2": {bold(), italic()}, 
		"H3": {bold(), italic()},
		"OtherCode": {foregroundColor(rgb(0x00,0x87,0xff))}
		
		// 
		//"Type": {foregroundColor(rgb(0x74,0x8B,0x00))},
		//"Identifier": {foregroundColor(rgb(0x48,0x5A,0x62))},
		//"Variable": {foregroundColor(rgb(0x26,0x8B,0xD2))},
		////"Constant": {foregroundColor(rgb(0xD3,0x36,0x82))},
		//"Constant": {foregroundColor(rgb(0xCB,0x4B,0x16))},
		//"Comment": {italic(), foregroundColor(rgb(0x8a,0x8a,0x8a))},
		//"Todo": {bold(), foregroundColor(rgb(0xaf,0x00,0x00))},
		////"Quote": {}, // no idea what this category means?
		//"MetaAmbiguity": {foregroundColor(rgb(0xaf,0x00,0x00)), bold(), italic()},
		//"MetaVariable": {foregroundColor( rgb(0x00,0x87,0xff))},
		//"MetaKeyword": {foregroundColor( rgb(0x85,0x99,0x00))},
		//// new categories
		//"StringLiteral": {foregroundColor(rgb(0x2A,0xA1,0x98))}
	));
}

void main() {
  registerLanguage("TyDown", "tydown", start[TyDown](str src, loc l) {
    return parse(#start[TyDown], src, l);
  });
  
  registerContributions("TyDown", { myCategories() });
}