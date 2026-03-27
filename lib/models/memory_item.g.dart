// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'memory_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MemoryItemAdapter extends TypeAdapter<MemoryItem> {
  @override
  final int typeId = 2;

  @override
  MemoryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MemoryItem(
      id: fields[0] as String,
      content: fields[1] as String,
      createdAt: fields[2] as DateTime,
      importance: fields[3] as double,
      category: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, MemoryItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.importance)
      ..writeByte(4)
      ..write(obj.category);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
