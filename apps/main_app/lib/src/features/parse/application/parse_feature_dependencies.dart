import 'package:nolive_app/src/shared/application/provider_catalog_use_cases.dart';

import 'inspect_parsed_room_use_case.dart';
import 'parse_room_input_use_case.dart';

class ParseFeatureDependencies {
  const ParseFeatureDependencies({
    required this.listProviderDescriptors,
    required this.parseRoomInput,
    required this.inspectParsedRoom,
  });

  final ListProviderDescriptorsUseCase listProviderDescriptors;
  final ParseRoomInputUseCase parseRoomInput;
  final InspectParsedRoomUseCase inspectParsedRoom;
}
