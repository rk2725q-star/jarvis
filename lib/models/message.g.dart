// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 0;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      id: fields[0] as String,
      content: fields[1] as String,
      isUser: fields[2] as bool,
      timestamp: fields[3] as DateTime,
      sessionId: fields[7] as String,
      provider: fields[4] as String?,
      model: fields[5] as String?,
      isStreaming: fields[6] as bool,
      tokenCount: fields[8] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.isUser)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.provider)
      ..writeByte(5)
      ..write(obj.model)
      ..writeByte(6)
      ..write(obj.isStreaming)
      ..writeByte(7)
      ..write(obj.sessionId)
      ..writeByte(8)
      ..write(obj.tokenCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
